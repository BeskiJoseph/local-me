import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';

export class RiskEngine {
    /**
     * Compare incoming request fingerprint against the stored session fingerprint
     * @param {Object} storedSession - Refresh token document from database
     * @param {Object} currentContext - Handled via deviceContext middleware
     * @returns {number} The calculated risk score for this attempt
     */
    static evaluateRefreshRisk(storedSession, currentContext) {
        let riskScore = 0;

        // Device mismatch is handled by strict check in the route, but we leave it here for fallback
        if (storedSession.deviceIdHash !== currentContext.deviceIdHash) {
            riskScore += 20;
        }

        // Medium risk: The user agent changed (browser update, different client app build)
        if (storedSession.userAgentHash !== currentContext.userAgentHash) {
            riskScore += 10;
        }

        // Low risk: IP changed (user switched from Wi-Fi to cellular, standard behavior)
        if (storedSession.ipHash !== currentContext.ipHash) {
            riskScore += 5;
        }

        return riskScore;
    }

    /**
     * Decays the accumulated risk score based on hours since last seen.
     * Subtracts 5 points for every 6 hours of clean history.
     */
    static calculateDecayedRisk(tokenData) {
        let riskScore = tokenData.riskScore || 0;
        if (!tokenData.lastSeenAt || riskScore === 0) return riskScore;

        const msSinceLastSeen = Date.now() - new Date(tokenData.lastSeenAt).getTime();
        const hoursSinceLastSeen = msSinceLastSeen / (1000 * 60 * 60);

        if (hoursSinceLastSeen >= 6) {
            const decayAmount = Math.floor(hoursSinceLastSeen / 6) * 5;
            riskScore = Math.max(0, riskScore - decayAmount);
        }

        return riskScore;
    }

    /**
     * Threshold for a complete, immediate session burn and token version bump
     * e.g., Stolen token replayed on an entirely different platform
     */
    static shouldHardBurn(riskScore) {
        return riskScore >= 50;
    }

    /**
     * Threshold for rejecting the refresh and requiring a normal re-login, 
     * without punishing the user's other active sessions.
     */
    static shouldSoftLock(riskScore) {
        return riskScore >= 25;
    }

    /**
     * Temporal & Behavioral Session Continuity Intelligence
     * Checks for concurrent refresh races, velocity, and session limits.
     */
    static async evaluateSessionContinuity(userId, currentIpHash) {
        try {
            // Get up to 15 recent tokens to evaluate velocity and active session count
            const tokensSnapshot = await db.collection('refresh_tokens')
                .where('userId', '==', userId)
                .orderBy('createdAt', 'desc')
                .limit(15)
                .get();

            let activeSessionsCount = 0;
            let refreshesLastMinute = 0;
            let refreshesLast3Seconds = 0;
            let lastRefreshIpHash = null;

            const nowMs = Date.now();

            tokensSnapshot.forEach(doc => {
                const data = doc.data();
                if (!data.isRevoked) {
                    activeSessionsCount++;
                }

                // Treat createdAt as the time of the refresh event
                const ageMs = nowMs - new Date(data.createdAt).getTime();

                if (ageMs <= 60 * 1000) {
                    refreshesLastMinute++;
                }

                if (ageMs <= 3 * 1000) {
                    refreshesLast3Seconds++;
                    // Grab the IP of the most recent prior refresh
                    if (!lastRefreshIpHash && data.ipHash) {
                        lastRefreshIpHash = data.ipHash;
                    }
                }
            });

            // 1. Concurrent Refresh Race Condition (Different IP within 3 secs)
            if (refreshesLast3Seconds >= 1 && lastRefreshIpHash && lastRefreshIpHash !== currentIpHash) {
                return { action: 'hard_burn', reason: 'concurrent_refresh_different_ip' };
            }

            // 2. Token Refresh Storm (Frequency Abuse)
            let additionalRisk = 0;
            if (refreshesLastMinute >= 5) {
                additionalRisk += 30; // Suspicious high-frequency rotation
            }

            // 3. Active Session Cap Check
            if (activeSessionsCount > 10) {
                additionalRisk += 20; // Having > 10 active refresh tokens is highly anomalous
            }

            return { action: 'ok', additionalRisk };
        } catch (err) {
            logger.error({ error: err.message, userId }, 'Failed to evaluate session continuity');
            return { action: 'ok', additionalRisk: 0 };
        }
    }

    /**
     * Burn ALL sessions for a user globally (Full Containment)
     * Used exclusively when malicious compromise is highly confident (e.g. replay attack)
     */
    static async executeFullSessionBurn(userId, reason) {
        try {
            logger.warn({ userId, reason }, '🔥 Executing Full Session Burn');

            // 1. Invalidate all existing refresh tokens
            const tokensSnapshot = await db.collection('refresh_tokens')
                .where('userId', '==', userId)
                .where('isRevoked', '==', false)
                .get();

            const batch = db.batch();
            tokensSnapshot.forEach((doc) => {
                batch.update(doc.ref, {
                    isRevoked: true,
                    revokedReason: reason,
                    riskScore: 0, // Clear the risk score
                    revokedAt: new Date().toISOString()
                });
            });

            // 2. Bump the global token version to invalidate any live JWT Access Tokens in the wild
            const userRef = db.collection('users').doc(userId);
            batch.update(userRef, {
                tokenVersion: admin.firestore.FieldValue.increment(1),
                securityLastBurned: new Date().toISOString()
            });

            await batch.commit();
            logger.warn({ userId, revokedCount: tokensSnapshot.size }, '✅ Sessions burned, Version incremented');
        } catch (error) {
            logger.error({ userId, error: error.message }, '❌ Failed to execute session burn');
        }
    }
}
