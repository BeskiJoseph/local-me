import logger from '../utils/logger.js';
import { globalLimiterStore } from './MemoryLimiterService.js';

class PenaltyBox {
    constructor() {
        // Single VM Global Pressure Counter
        this.globalHits = 0;
        this.lastSecond = Math.floor(Date.now() / 1000);
    }

    /**
     * @param {string} key - Usually IP or User ID concatenated with action (e.g. "auth:192.168.1.1")
     * @param {number} maxRequests - Allowed hits per window
     * @param {number} windowMs - Time window
     * @returns {object} { allowed: boolean, reason?: string, strikes: number }
     */
    checkLimit(key, maxRequests, windowMs) {
        // Global pressure check (Volumetric attacks)
        const nowSec = Math.floor(Date.now() / 1000);
        if (this.lastSecond !== nowSec) {
            this.lastSecond = nowSec;
            this.globalHits = 0;
        }
        this.globalHits++;

        if (this.globalHits > 2000) {
            logger.warn('🚨 Global pressure threshold exceeded (>2000 req/s)!');
            return { allowed: false, reason: 'global_pressure', strikes: 0 };
        }

        const blockKey = `block:${key}`;
        const reqKey = `req:${key}`;

        // 1. Check if currently heavily blocked (Penalty Box)
        // Store returns null if expired natively
        const blockRecord = globalLimiterStore.get(blockKey);
        if (blockRecord) {
            return { allowed: false, reason: 'progressive_block', strikes: blockRecord.strikes };
        }

        // 2. Track Request Rate
        let reqRecord = globalLimiterStore.get(reqKey);
        if (!reqRecord) {
            reqRecord = { count: 1 };
            globalLimiterStore.set(reqKey, reqRecord, windowMs);
            return { allowed: true, strikes: blockRecord?.strikes || 0 };
        }

        reqRecord.count++;
        // Update keeping the original TTL implicitly via not changing the actual expiry if possible,
        // Wait, standard sliding window resets TTL on each hit. We will reset TTL on hit for simplicity.
        globalLimiterStore.set(reqKey, reqRecord, windowMs);

        // 3. Trigger Block if exceeded
        if (reqRecord.count > maxRequests) {
            this.applyProgressivePenalty(key, blockRecord);
            return { allowed: false, reason: 'rate_limited', strikes: (blockRecord?.strikes || 0) + 1 };
        }

        return { allowed: true, strikes: blockRecord?.strikes || 0 };
    }

    applyProgressivePenalty(key, previousBlockRecord) {
        const strikes = previousBlockRecord ? previousBlockRecord.strikes + 1 : 1;

        // The Progressive Escalation Curve:
        // 1st strike -> block for 5 minutes
        // 2nd strike -> block for 30 minutes
        // 3rd+ strike -> block for 24 hours
        let penaltyMinutes = 5;
        if (strikes === 2) penaltyMinutes = 30;
        else if (strikes >= 3) penaltyMinutes = 24 * 60;

        const penaltyMs = penaltyMinutes * 60 * 1000;

        const blockKey = `block:${key}`;
        const reqKey = `req:${key}`;

        globalLimiterStore.set(blockKey, { strikes }, penaltyMs);
        globalLimiterStore.delete(reqKey); // Clear request counter as they are now fully blocked

        logger.warn({ key, strikes, penaltyMinutes }, `🚨 Progressive Penalty Applied`);
    }
}

export const globalPenaltyBox = new PenaltyBox();
