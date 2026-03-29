import logger from '../utils/logger.js';
import { globalLimiterStore } from './MemoryLimiterService.js';

/**
 * 🛡️ Interaction Guard (Layer 4 Graph Integrity)
 * Enforces Hybrid Behavioral Model:
 * - Mild violations (rapid toggle): Shadow suppression (return 200, no DB action)
 * - Severe violations (burst cap): Strict 429 rejection
 */
export class InteractionGuard {

    // Internal generic counter
    static _incrementCounter(key, ttlMs) {
        const now = Date.now();
        let record = globalLimiterStore.get(key);

        if (!record) {
            record = { count: 1, history: [now] };
        } else {
            record.count += 1;
            record.history.push(now);
            // Prune old history optionally
            record.history = record.history.filter(t => now - t < ttlMs);
            record.count = record.history.length;
        }

        globalLimiterStore.set(key, record, ttlMs);
        return record.count;
    }

    /**
     * Reusable cycle detector for Pair Toggles (e.g. Like/Unlike, Follow/Unfollow)
     * Return formats: { action: 'allow' | 'shadow' | 'block' }
     */
    static checkPairToggle(userId, targetId, prefix, cooldownMs = 3000, cycleLimit = 3, cycleWindowMs = 60000) {
        const key = `${prefix}:${userId}:${targetId}`;
        const now = Date.now();

        let record = globalLimiterStore.get(key);
        if (!record) {
            // First time or expired cooldown
            globalLimiterStore.set(key, { lastToggle: now, cycleCount: 1 }, cycleWindowMs);
            return { action: 'allow' };
        }

        // 1. Pair Toggle Cooldown (< 3 seconds) -> Shadow (Ignore, protect DB)
        if (now - record.lastToggle < cooldownMs) {
            logger.warn({ userId, targetId, prefix }, 'Pair toggle cooldown hit (Shadow Suppressed)');
            record.lastToggle = now;
            globalLimiterStore.set(key, record, cycleWindowMs);
            return { action: 'shadow' };
        }

        // 2. Cycling Detection (Like -> Unlike -> Like rapid cycling)
        record.cycleCount += 1;
        record.lastToggle = now;

        if (record.cycleCount >= cycleLimit) {
            logger.error({ userId, targetId, prefix }, 'Graph Abuse: Cycling detected. Blocking user action.');
            // Penalize by extending expiration window
            globalLimiterStore.set(key, record, 5 * 60 * 1000); // Block from this pair for 5 mins
            return { action: 'block' }; // 429
        }

        globalLimiterStore.set(key, record, cycleWindowMs);
        return { action: 'allow' };
    }

    /**
     * Check global action velocity limits for a user (Likes, Follows)
     */
    static checkVelocity(userId, prefix, minuteLimit, hourLimit) {
        const minKey = `${prefix}_min:${userId}`;
        const hrKey = `${prefix}_hr:${userId}`;

        const minCount = this._incrementCounter(minKey, 60 * 1000);
        const hrCount = this._incrementCounter(hrKey, 60 * 60 * 1000);

        if (minCount > minuteLimit || hrCount > hourLimit) {
            logger.warn({ userId, prefix, minCount, hrCount }, 'Graph Abuse: Global velocity exceeded. Blocking.');
            return { action: 'block' }; // Severe: 429
        }

        return { action: 'allow' };
    }

    /**
     * Check Follow specific constraints
     */
    static checkFollowVelocity(userId, targetId) {
        // Pair constraint: 1 toggle per 3s, max 3 cycles in 60s
        const pair = this.checkPairToggle(userId, targetId, 'follow', 3000, 3, 60000);
        if (pair.action !== 'allow') return pair;

        // Global constraint: 5 per min, 30 per hour
        return this.checkVelocity(userId, 'follow', 5, 30);
    }

    /**
     * Check Like specific constraints
     */
    static checkLikeVelocity(userId, postId) {
        // Pair constraint: 1 toggle per 3s, max 3 cycles in 60s
        const pair = this.checkPairToggle(userId, postId, 'like', 3000, 3, 60000);
        if (pair.action !== 'allow') return pair;

        // Global constraint: 20 per min, 60 per hour
        return this.checkVelocity(userId, 'like', 20, 60);
    }
}
