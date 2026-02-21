import express from 'express';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';

const router = express.Router();

/**
 * @route   GET /api/notifications
 * @desc    Get current user notifications
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const snapshot = await db.collection('notifications')
            .where('toUserId', '==', req.user.uid)
            .orderBy('timestamp', 'desc')
            .limit(50)
            .get();

        const notifications = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
            timestamp: doc.data().timestamp?.toDate()?.toISOString()
        }));

        return res.json({ data: notifications });
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
