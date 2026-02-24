import express from 'express';
import jwt from 'jsonwebtoken';
import { auth, db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import crypto from 'crypto';
import { deviceContext } from '../middleware/deviceContext.js';
import { RiskEngine } from '../services/RiskEngine.js';

const router = express.Router();

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET;

/**
 * @route   POST /api/auth/token
 * @desc    Exchange Firebase ID Token for custom Access/Refresh Token pair
 * @access  Public (Requires Firebase Token)
 */
router.post('/token', deviceContext, async (req, res) => {
    try {
        const { idToken } = req.body;
        if (!idToken) {
            return res.status(400).json({ success: false, error: 'Firebase ID Token is required' });
        }

        // 1. Verify secrets are configured
        if (!ACCESS_SECRET || !REFRESH_SECRET) {
            logger.error('❌ JWT secrets are not configured in environment variables');
            return res.status(500).json({ success: false, error: 'Internal server configuration error' });
        }

        // 2. Verify Firebase Token
        logger.debug({
            tokenLength: idToken?.length,
            tokenPrefix: idToken ? `${idToken.substring(0, 10)}...${idToken.substring(idToken.length - 10)}` : 'null'
        }, 'Attempting Firebase token verification');

        let decodedToken;
        try {
            decodedToken = await auth.verifyIdToken(idToken);
        } catch (verifyError) {
            logger.error({
                error: verifyError.message,
                code: verifyError.code
            }, 'Firebase verifyIdToken failed');
            return res.status(401).json({
                success: false,
                error: 'Invalid or expired Firebase token',
                debug: {
                    message: verifyError.message,
                    code: verifyError.code
                }
            });
        }

        const uid = decodedToken.uid;

        // 3. Get or Initialize User Security Version
        let userDoc = await db.collection('users').doc(uid).get();
        let tokenVersion = 1;

        if (userDoc.exists) {
            tokenVersion = userDoc.data().tokenVersion || 1;

            // Auto-heal legacy minimal documents missing essential schema fields
            const data = userDoc.data();
            if (!data.username || !data.displayName) {
                const baseName = decodedToken.name || (decodedToken.email ? decodedToken.email.split('@')[0] : 'user');
                const cleanBase = baseName.toLowerCase().replace(/[^a-z0-9]/g, '');

                await db.collection('users').doc(uid).set({
                    displayName: data.displayName || decodedToken.name || '',
                    profileImageUrl: data.profileImageUrl || decodedToken.picture || '',
                    username: data.username || `${cleanBase}${Math.floor(1000 + Math.random() * 9000)}`
                }, { merge: true });
            }
        } else {
            // New user case: Initialize version WITH full frontend presentation schema
            const baseName = decodedToken.name || (decodedToken.email ? decodedToken.email.split('@')[0] : 'user');
            const cleanBase = baseName.toLowerCase().replace(/[^a-z0-9]/g, '');
            const generatedUsername = `${cleanBase}${Math.floor(1000 + Math.random() * 9000)}`;

            await db.collection('users').doc(uid).set({
                tokenVersion: 1,
                email: decodedToken.email || '',
                role: 'user',
                status: 'active',
                displayName: decodedToken.name || '',
                profileImageUrl: decodedToken.picture || '',
                username: generatedUsername,
                createdAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });
        }

        // 4. Generate custom pair with Versioning & Rotation Support
        const jti = crypto.randomUUID();

        const accessToken = jwt.sign(
            { uid, email: decodedToken.email, version: tokenVersion, provider: 'firebase' },
            ACCESS_SECRET,
            { expiresIn: '15m' }
        );

        const refreshToken = jwt.sign(
            { uid, version: tokenVersion, jti },
            REFRESH_SECRET,
            { expiresIn: '30d' }
        );

        // 5. Store refresh token for rotation tracking
        try {
            await db.collection('refresh_tokens').doc(jti).set({
                userId: uid,
                version: tokenVersion,
                isRevoked: false,
                parentJti: null, // Root token
                deviceIdHash: req.deviceContext.deviceIdHash,
                userAgentHash: req.deviceContext.userAgentHash,
                ipHash: req.deviceContext.ipHash,
                riskScore: 0,
                lastSeenAt: new Date().toISOString(),
                createdAt: new Date().toISOString(),
                expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            });
        } catch (dbError) {
            logger.warn({ error: dbError.message }, 'Failed to store refresh token in DB');
        }

        logger.info({ userId: uid, version: tokenVersion }, 'Security-mature tokens issued');

        return res.json({
            success: true,
            data: {
                accessToken,
                refreshToken,
                expiresIn: 900
            }
        });
    } catch (error) {
        logger.error({ error: error.message, stack: error.stack }, 'Token exchange unexpected error');
        return res.status(500).json({ success: false, error: 'Internal server error during token exchange' });
    }
});

/**
 * @route   POST /api/auth/refresh
 * @desc    Get new Access Token using Refresh Token
 * @access  Public
 */
router.post('/refresh', deviceContext, async (req, res) => {
    try {
        const { refreshToken } = req.body;
        if (!refreshToken) {
            return res.status(400).json({ success: false, error: 'Refresh token is required' });
        }

        // 1. Verify Signature & Payload
        const payload = jwt.verify(refreshToken, REFRESH_SECRET);
        const { uid, version, jti } = payload;

        if (!jti) {
            return res.status(401).json({ success: false, error: 'Legacy token: Please re-login' });
        }

        // 2. Database Validation (Anti-Replay)
        const tokenDoc = await db.collection('refresh_tokens').doc(jti).get();
        if (!tokenDoc.exists || tokenDoc.data().isRevoked) {
            logger.warn({ userId: uid, jti }, 'Potential Replay Attack Detected / Revoked Token Usage');

            // 🔥 Instagram-Level Full Containment: Burn all sessions unconditionally
            await RiskEngine.executeFullSessionBurn(uid, 'refresh_token_replay_detected');

            return res.status(401).json({ success: false, error: 'Session compromised. Please log in again.' });
        }

        const tokenData = tokenDoc.data();

        // 3. Version Check (Global Kill Switch)
        const userDoc = await db.collection('users').doc(uid).get();
        const currentVersion = userDoc.exists ? (userDoc.data().tokenVersion || 1) : 1;

        if (version !== currentVersion) {
            return res.status(401).json({ success: false, error: 'Security version mismatch' });
        }

        // 🧠 3.1 Strict Hybrid Check: Device ID Mismatch on Refresh = Immediate Burn
        if (tokenData.deviceIdHash !== req.deviceContext.deviceIdHash) {
            logger.error({ userId: uid, jti }, 'Strict Device ID Mismatch on Refresh Token');
            await RiskEngine.executeFullSessionBurn(uid, 'strict_device_mismatch');
            return res.status(401).json({ success: false, error: 'Security alert: Session compromised.' });
        }

        // 🧠 3.2 Session Continuity Engine (Temporal/Behavioral Checks)
        const continuityResult = await RiskEngine.evaluateSessionContinuity(uid, req.deviceContext.ipHash);
        if (continuityResult.action === 'hard_burn') {
            await RiskEngine.executeFullSessionBurn(uid, continuityResult.reason);
            return res.status(401).json({ success: false, error: 'Security alert: Session compromised.' });
        }

        // 🧠 3.5 Use Risk Engine to monitor anomalies across rotations (with decay)
        const decayedRisk = RiskEngine.calculateDecayedRisk(tokenData);
        const risk = RiskEngine.evaluateRefreshRisk(tokenData, req.deviceContext);
        let cumulativeRisk = decayedRisk + risk + (continuityResult.additionalRisk || 0);

        if (RiskEngine.shouldHardBurn(cumulativeRisk)) {
            await RiskEngine.executeFullSessionBurn(uid, `accumulated_risk_score_${cumulativeRisk}`);
            return res.status(401).json({ success: false, error: 'Security alert: Session compromised.' });
        }

        if (RiskEngine.shouldSoftLock(cumulativeRisk)) {
            // Update risk score in db before rejecting, so they stay locked until actual re-login
            await tokenDoc.ref.update({ riskScore: cumulativeRisk, lastSeenAt: new Date().toISOString() });
            return res.status(401).json({ success: false, error: 'Suspicious activity detected. Please re-authenticate.' });
        }

        // 4. ROTATION: Invalidate old token tracking
        const newJti = crypto.randomUUID();
        await tokenDoc.ref.update({
            isRevoked: true,
            riskScore: cumulativeRisk,
            rotatedToJti: newJti
        });

        // 5. ISSUE NEW PAIR
        const newAccessToken = jwt.sign(
            { uid, provider: 'custom', version: currentVersion },
            ACCESS_SECRET,
            { expiresIn: '15m' }
        );

        const newRefreshToken = jwt.sign(
            { uid, version: currentVersion, jti: newJti },
            REFRESH_SECRET,
            { expiresIn: '30d' }
        );

        // Store new refresh token
        await db.collection('refresh_tokens').doc(newJti).set({
            userId: uid,
            version: currentVersion,
            isRevoked: false,
            parentJti: jti, // Maintain strict chain
            deviceIdHash: req.deviceContext.deviceIdHash,
            userAgentHash: req.deviceContext.userAgentHash,
            ipHash: req.deviceContext.ipHash,
            riskScore: cumulativeRisk,
            lastSeenAt: new Date().toISOString(),
            createdAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        });

        return res.json({
            success: true,
            data: {
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
                expiresIn: 900
            }
        });
    } catch (error) {
        logger.error({ error: error.message }, 'Refresh operation failed');
        return res.status(401).json({ success: false, error: 'Invalid or expired refresh token' });
    }
});

/**
 * @route   GET /api/auth/debug
 * @desc    Debug endpoint to verify Firebase project config
 * @access  Public
 */
router.get('/debug', (req, res) => {
    res.json({
        success: true,
        data: {
            projectId: process.env.FIREBASE_PROJECT_ID,
            nodeEnv: process.env.NODE_ENV,
            hasPrivateKey: !!process.env.FIREBASE_PRIVATE_KEY,
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
            timestamp: new Date().toISOString()
        }
    });
});

export default router;
