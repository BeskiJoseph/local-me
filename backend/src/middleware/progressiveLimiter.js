import { globalPenaltyBox } from '../services/PenaltyBox.js';
import { logSecurityEvent } from '../utils/logger.js';

// Centralized Routing Policy Map
export const POLICIES = {
    auth: { max: 10, window: 2 * 60 * 1000 },
    otp: { max: 10, window: 2 * 60 * 1000 },
    feed: { max: 120, window: 60 * 1000 },
    create_post: { max: 5, window: 60 * 1000 },
    like: { max: 40, window: 60 * 1000 },
    follow: { max: 20, window: 60 * 1000 },
    upload: { max: 20, window: 15 * 60 * 1000 },
    chat_message: { max: 20, window: 60 * 1000 }, // ~3s per message average
    api: { max: 300, window: 15 * 60 * 1000 }, // General API route limit
    health: { max: 60, window: 60 * 1000 }
};

/**
 * High-speed in-memory progressive rate limiter
 * @param {string} action - Context mapped to POLICIES
 * @param {boolean} useUserId - Should we limit per actual UID or IP?
 */
export const progressiveLimiter = (action, useUserId = false) => {
    const policy = POLICIES[action] || { max: 100, window: 60 * 1000 };

    return (req, res, next) => {
        // 'trust proxy' is handled globally in app.js so req.ip is correct behind Nginx
        const identifier = (useUserId && req.user?.uid) ? req.user.uid : req.ip;
        const key = `${action}:${identifier}`;

        const result = globalPenaltyBox.checkLimit(key, policy.max, policy.window);

        if (!result.allowed) {
            logSecurityEvent('RATE_LIMIT_EXCEEDED', {
                ip: req.ip,
                userId: req.user?.uid,
                action,
                reason: result.reason,
                strikes: result.strikes
            });

            if (result.reason === 'global_pressure') {
                return res.status(503).json({
                    success: false,
                    error: 'Service temporarily overloaded. Please try again soon.',
                    cooldown: true
                });
            }

            const penaltyTime = result.strikes >= 3 ? '24 hours' : (result.strikes === 2 ? '30 minutes' : '5 minutes');

            return res.status(429).json({
                success: false,
                error: `Too many requests. Temporary cooldown applied for ${penaltyTime}.`,
                cooldown: true
            });
        }

        next();
    };
};
