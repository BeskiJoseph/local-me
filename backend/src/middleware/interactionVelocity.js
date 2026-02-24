import { InteractionGuard } from '../services/InteractionGuard.js';
import logger from '../utils/logger.js';

/**
 * Middleware wrapper for InteractionGuard. 
 * Prevents metric inflation, follower spam, and graph pollution.
 */
export function enforceFollowVelocity(req, res, next) {
    const userId = req.user?.uid;
    const targetUserId = req.body?.targetUserId;

    if (!userId || !targetUserId) return next();

    const result = InteractionGuard.checkFollowVelocity(userId, targetUserId);

    if (result.action === 'block') {
        return res.status(429).json({
            success: false,
            error: 'You are performing this action too fast. Please slow down.'
        });
    }

    if (result.action === 'shadow') {
        // Hybrid Model: Accept request normally but drop it silently to confuse the bot 
        // without signaling that they've been rate-limited.
        return res.json({
            success: true,
            data: { status: 'active', suppressed: true },
            error: null
        });
    }

    next();
}

export function enforceLikeVelocity(req, res, next) {
    const userId = req.user?.uid;
    const postId = req.body?.postId;

    if (!userId || !postId) return next();

    const result = InteractionGuard.checkLikeVelocity(userId, postId);

    if (result.action === 'block') {
        return res.status(429).json({
            success: false,
            error: 'You are liking too many posts. Please slow down.'
        });
    }

    if (result.action === 'shadow') {
        // Silently drop the toggle but pretend it worked
        return res.json({
            success: true,
            data: { status: 'active', suppressed: true },
            error: null
        });
    }

    next();
}
