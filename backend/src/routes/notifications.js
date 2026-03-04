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
        const { type } = req.query;
        logger.info({ userId: req.user.uid, type }, 'Fetching notifications');

        let query = db.collection('notifications')
            .where('toUserId', '==', req.user.uid);

        if (type) {
            query = query.where('type', '==', type);
        }

        let snapshot;
        try {
            // Primary query: orderBy timestamp (requires composite index)
            snapshot = await query
                .orderBy('timestamp', 'desc')
                .limit(50)
                .get();
        } catch (indexError) {
            // Fallback: if composite index doesn't exist, query without orderBy
            logger.warn({ error: indexError.message }, 'Notifications index error, falling back to unordered query');
            snapshot = await query
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
 * @route   PATCH /api/notifications/read-all
 * @desc    Mark all unread notifications as read
 */
router.patch('/read-all', authenticate, async (req, res, next) => {
    try {
        const snapshot = await db.collection('notifications')
            .where('toUserId', '==', req.user.uid)
            .where('isRead', '==', false)
            .limit(500)
            .get();

        if (snapshot.empty) return res.json({ success: true, count: 0 });

        const batch = db.batch();
        snapshot.docs.forEach(doc => {
            batch.update(doc.ref, { isRead: true });
        });

        await batch.commit();

        return res.json({ success: true, count: snapshot.size });
    } catch (err) {
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
