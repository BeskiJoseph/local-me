import logger from '../utils/logger.js';

class PenaltyBox {
    constructor() {
        this.requests = new Map(); // Tracks active requests: { count, firstRequest }
        this.blocks = new Map();   // Tracks active blocks: { expiresAt, strikes, lastDecay }

        // Single VM Global Pressure Counter
        this.globalHits = 0;
        this.lastSecond = Math.floor(Date.now() / 1000);

        // Memory Leak Prevention: Cleanup expired records every 5 minutes
        setInterval(() => this.cleanup(), 5 * 60 * 1000);
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

        const now = Date.now();

        // 1. Check if currently heavily blocked (Penalty Box)
        const blockRecord = this.blocks.get(key);
        if (blockRecord && blockRecord.expiresAt > now) {
            return { allowed: false, reason: 'progressive_block', strikes: blockRecord.strikes };
        }

        // 2. Track Request Rate
        let reqRecord = this.requests.get(key);
        if (!reqRecord || (now - reqRecord.firstRequest > windowMs)) {
            reqRecord = { count: 1, firstRequest: now };
            this.requests.set(key, reqRecord);
            return { allowed: true, strikes: blockRecord?.strikes || 0 };
        }

        reqRecord.count++;

        // 3. Trigger Block if exceeded
        if (reqRecord.count > maxRequests) {
            this.applyProgressivePenalty(key, blockRecord);
            return { allowed: false, reason: 'rate_limited', strikes: (blockRecord?.strikes || 0) + 1 };
        }

        // 4. Memory Cap to prevent exhaustion
        const MAX_ENTRIES = 100000;
        if (this.requests.size > MAX_ENTRIES) {
            logger.warn('🚨 Memory cap reached in PenaltyBox requests Map. Clearing to prevent exhaustion.');
            this.requests.clear();
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

        const expiresAt = Date.now() + (penaltyMinutes * 60 * 1000);

        this.blocks.set(key, { expiresAt, strikes, lastDecay: 0 });
        this.requests.delete(key); // Clear request counter as they are now fully blocked

        logger.warn({ key, strikes, penaltyMinutes }, `🚨 Progressive Penalty Applied`);
    }

    cleanup() {
        const now = Date.now();
        for (const [key, block] of this.blocks.entries()) {
            if (now > block.expiresAt) {
                // Decay strikes slowly (1 per 24 hours) instead of full reset
                if (!block.lastDecay || now > block.lastDecay + (24 * 60 * 60 * 1000)) {
                    block.strikes = Math.max(0, block.strikes - 1);
                    block.lastDecay = now;
                }

                if (block.strikes === 0) {
                    this.blocks.delete(key);
                }
            }
        }
    }
}

export const globalPenaltyBox = new PenaltyBox();
