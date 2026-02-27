import express from 'express';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';
import logger from '../utils/logger.js';

const router = express.Router();

/**
 * @route   GET /api/notifications
 * @desc    Get current user notifications
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        logger.info({ userId: req.user.uid }, 'Fetching notifications');

        let snapshot;
        try {
            // Primary query: orderBy timestamp (requires composite index)
            snapshot = await db.collection('notifications')
                .where('toUserId', '==', req.user.uid)
                .orderBy('timestamp', 'desc')
                .limit(50)
                .get();
        } catch (indexError) {
            // Fallback: if composite index doesn't exist, query without orderBy
            logger.warn({ error: indexError.message }, 'Notifications index error, falling back to unordered query');
            snapshot = await db.collection('notifications')
                .where('toUserId', '==', req.user.uid)
                .limit(50)
                .get();
        }

        logger.info({ count: snapshot.docs.length, userId: req.user.uid }, 'Notifications fetched');

        const notifications = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
                id: doc.id,
                ...data,
                timestamp: data.timestamp?.toDate?.()
                    ? data.timestamp.toDate().toISOString()
                    : data.createdAt?.toDate?.()
                        ? data.createdAt.toDate().toISOString()
                        : new Date().toISOString()
            };
        });

        // Sort by timestamp descending (in case fallback query was used)
        notifications.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

        return res.json({ success: true, data: notifications });
    } catch (err) {
        logger.error({ error: err.message, stack: err.stack }, 'Notifications fetch error');
        next(err);
    }
});

/**
 * @route   PATCH /api/notifications/:id/read
 * @desc    Mark a notification as read
 */
router.patch('/:id/read', authenticate, async (req, res, next) => {
    try {
        const docRef = db.collection('notifications').doc(req.params.id);
        const doc = await docRef.get();

        if (!doc.exists) return res.status(404).json({ error: 'Notification not found' });
        if (doc.data().toUserId !== req.user.uid) return res.status(403).json({ error: 'Unauthorized' });

        await docRef.update({ isRead: true });
        return res.json({ success: true });
    } catch (err) {
        next(err);
    }
});

export default router;
