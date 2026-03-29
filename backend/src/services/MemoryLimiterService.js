import logger from '../utils/logger.js';

/**
 * BUG-010 & BUG-029: Unified In-Memory Store for all Rate Limiting
 * Centralizes memory management, expiration, and key tracking for:
 * 1. Express Rate Limits (rateLimiter.js)
 * 2. Progressive Penalty Limits (PenaltyBox.js)
 * 3. Behavioral Interaction Limits (InteractionGuard.js)
 * 
 * Future migration to Redis only requires rewriting this single class.
 */
class MemoryLimiterService {
    constructor() {
        this.store = new Map();
        
        // Clean up expired records every 5 minutes to prevent OOM errors
        setInterval(() => this.cleanup(), 5 * 60 * 1000);
    }

    /**
     * Set a record with an explicit TTL (Time To Live).
     * @param {string} key 
     * @param {any} data 
     * @param {number} ttlMs 
     */
    set(key, data, ttlMs) {
        const expiresAt = Date.now() + ttlMs;
        this.store.set(key, { data, expiresAt });
    }

    /**
     * Get a record, strictly observing its TTL. Returns null if expired.
     * @param {string} key 
     * @returns {any}
     */
    get(key) {
        const record = this.store.get(key);
        if (!record) return null;

        if (Date.now() > record.expiresAt) {
            this.store.delete(key);
            return null;
        }

        return record.data;
    }

    delete(key) {
        this.store.delete(key);
    }

    get size() {
        return this.store.size;
    }

    clear() {
        this.store.clear();
    }

    cleanup() {
        const now = Date.now();
        let deleted = 0;
        for (const [key, record] of this.store.entries()) {
            if (now > record.expiresAt) {
                this.store.delete(key);
                deleted++;
            }
        }
        
        if (deleted > 1000) {
            logger.debug(`[MemoryLimiter] Purged ${deleted} expired limit records from centralized store`);
        }
    }
}

export const globalLimiterStore = new MemoryLimiterService();
