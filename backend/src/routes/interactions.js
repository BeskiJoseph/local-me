import express from 'express';
import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import authenticate from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import { body, validationResult } from 'express-validator';

const router = express.Router();

// Apply auth middleware to all interaction routes
router.use(authenticate);

/**
 * @route   POST /api/interactions/like
 * @desc    Like or unlike a post
 */
router.post(
    '/like',
    [
        body('postId').notEmpty().withMessage('Post ID is required'),
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

        const { postId } = req.body;
        const userId = req.user.uid;
        const likeId = `${postId}_${userId}`;
        const likeRef = db.collection('likes').doc(likeId);
        const postRef = db.collection('posts').doc(postId);

        try {
            await db.runTransaction(async (transaction) => {
                const likeDoc = await transaction.get(likeRef);
                const postDoc = await transaction.get(postRef);

                if (!postDoc.exists) throw new Error('Post not found');

                if (likeDoc.exists) {
                    // Unlike
                    transaction.delete(likeRef);
                    transaction.update(postRef, {
                        likeCount: admin.firestore.FieldValue.increment(-1)
                    });
                } else {
                    // Like
                    transaction.set(likeRef, {
                        postId,
                        userId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    transaction.update(postRef, {
                        likeCount: admin.firestore.FieldValue.increment(1)
                    });

                    // Trigger notification (async, non-blocking)
                    _sendNotificationInternal({
                        toUserId: postDoc.data().authorId,
                        fromUserId: userId,
                        fromUserName: req.user.displayName || 'Someone',
                        type: 'like',
                        postId,
                        postThumbnail: postDoc.data().thumbnailUrl || postDoc.data().mediaUrl
                    }).catch(err => logger.error('Notification Error', { err: err.message }));
                }
            });

            // Log Audit Action after successful transaction
            await AuditService.logAction({
                userId,
                action: 'POST_LIKE_TOGGLE',
                metadata: { postId },
                req
            });

            return res.json({
                success: true,
                data: { status: 'active' },
                error: null
            });
        } catch (error) {
            logger.error('Like Error', { error: error.message, postId, userId });
            return res.status(500).json({ error: error.message });
        }
    }
);

/**
 * @route   POST /api/interactions/comment
 * @desc    Add a comment to a post (Top-level comments collection)
 */
router.post(
    '/comment',
    [
        body('postId').notEmpty(),
        body('text').notEmpty(),
    ],
    async (req, res) => {
        const { postId, text } = req.body;
        const userId = req.user.uid;
        const postRef = db.collection('posts').doc(postId);
        const commentRef = db.collection('comments').doc();

        try {
            await db.runTransaction(async (transaction) => {
                const postDoc = await transaction.get(postRef);
                if (!postDoc.exists) throw new Error('Post not found');

                transaction.set(commentRef, {
                    postId, // Important: Top-level collection needs reference back to post
                    userId,
                    authorId: userId, // Align with frontend model field names
                    authorName: req.user.displayName || 'User',
                    authorProfileImage: req.user.photoURL,
                    text,
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });

                transaction.update(postRef, {
                    commentCount: admin.firestore.FieldValue.increment(1)
                });

                _sendNotificationInternal({
                    toUserId: postDoc.data().authorId,
                    fromUserId: userId,
                    fromUserName: req.user.displayName || 'Someone',
                    type: 'comment',
                    postId,
                    commentText: text,
                    postThumbnail: postDoc.data().thumbnailUrl || postDoc.data().mediaUrl
                }).catch(err => logger.error('Notification Error', { err: err.message }));
            });

            // Log Audit Action after successful transaction
            await AuditService.logAction({
                userId,
                action: 'POST_COMMENT_CREATED',
                metadata: { postId, commentId: commentRef.id },
                req
            });

            return res.json({
                success: true,
                data: { commentId: commentRef.id },
                error: null
            });
        } catch (error) {
            return res.status(500).json({ error: error.message });
        }
    }
);

/**
 * @route   POST /api/interactions/follow
 * @desc    Follow or unfollow a user
 */
router.post(
    '/follow',
    [
        body('targetUserId').notEmpty(),
    ],
    async (req, res) => {
        const { targetUserId } = req.body;
        const userId = req.user.uid;
        const followId = `${userId}_${targetUserId}`;
        const followRef = db.collection('follows').doc(followId);
        const currentUserRef = db.collection('users').doc(userId);
        const targetUserRef = db.collection('users').doc(targetUserId);

        try {
            await db.runTransaction(async (transaction) => {
                const followDoc = await transaction.get(followRef);

                if (followDoc.exists) {
                    transaction.delete(followRef);
                    transaction.update(currentUserRef, {
                        followingCount: admin.firestore.FieldValue.increment(-1)
                    });
                    transaction.update(targetUserRef, {
                        subscribers: admin.firestore.FieldValue.increment(-1)
                    });
                } else {
                    transaction.set(followRef, {
                        followerId: userId,
                        followingId: targetUserId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    transaction.update(currentUserRef, {
                        followingCount: admin.firestore.FieldValue.increment(1)
                    });
                    transaction.update(targetUserRef, {
                        subscribers: admin.firestore.FieldValue.increment(1)
                    });

                    _sendNotificationInternal({
                        toUserId: targetUserId,
                        fromUserId: userId,
                        fromUserName: req.user.displayName || 'Someone',
                        type: 'follow'
                    }).catch(err => logger.error('Notification Error', { err: err.message }));
                }
            });
            return res.json({
                success: true,
                data: { status: 'active' },
                error: null
            });
        } catch (error) {
            return res.status(500).json({ error: error.message });
        }
    }
);

/**
 * @route   POST /api/interactions/event/join
 * @desc    Join or leave an event
 */
router.post(
    '/event/join',
    [
        body('eventId').notEmpty(),
    ],
    async (req, res) => {
        const { eventId } = req.body;
        const userId = req.user.uid;
        const eventRef = db.collection('posts').doc(eventId);
        const attendanceId = `${eventId}_${userId}`;
        const attendanceRef = db.collection('event_attendance').doc(attendanceId);

        try {
            await db.runTransaction(async (transaction) => {
                const eventDoc = await transaction.get(eventRef);
                const attendanceDoc = await transaction.get(attendanceRef);

                if (!eventDoc.exists) throw new Error('Event not found');

                if (attendanceDoc.exists) {
                    transaction.delete(attendanceRef);
                    transaction.update(eventRef, {
                        attendeeCount: admin.firestore.FieldValue.increment(-1)
                    });
                } else {
                    transaction.set(attendanceRef, {
                        eventId,
                        userId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    transaction.update(eventRef, {
                        attendeeCount: admin.firestore.FieldValue.increment(1)
                    });
                }
            });
            return res.json({
                success: true,
                data: { status: 'active' },
                error: null
            });
        } catch (error) {
            return res.status(500).json({ error: error.message });
        }
    }
);

// Helper for notifications (mirrors existing Firestore logic)
async function _sendNotificationInternal({ toUserId, fromUserId, fromUserName, type, postId, postThumbnail, commentText }) {
    if (!toUserId || toUserId === fromUserId) return;

    // Construct data object without undefined values
    const notificationData = {
        toUserId,
        fromUserId,
        fromUserName,
        type,
        isRead: false,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
    };

    if (postId !== undefined) notificationData.postId = postId;
    if (postThumbnail !== undefined) notificationData.postThumbnail = postThumbnail;
    if (commentText !== undefined) notificationData.commentText = commentText;

    await db.collection('notifications').add(notificationData);
}

/**
 * @route   GET /api/interactions/comments/:postId
 * @desc    Get comments for a post
 */
router.get('/comments/:postId', authenticate, async (req, res, next) => {
    try {
        const snapshot = await db.collection('comments')
            .where('postId', '==', req.params.postId)
            .orderBy('createdAt', 'desc')
            .get();

        const comments = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
            createdAt: doc.data().createdAt?.toDate()?.toISOString()
        }));

        return res.json({
            success: true,
            data: comments,
            error: null
        });
    } catch (err) {
        next(err);
    }
});
/**
 * @route   POST /api/interactions/likes/batch
 * @desc    Check likes for multiple post IDs in a single call (Optimized for feed)
 */
router.post('/likes/batch', authenticate, async (req, res, next) => {
    try {
        const { postIds } = req.body;
        if (!postIds || !Array.isArray(postIds) || postIds.length === 0) {
            return res.json({ success: true, data: {}, error: null });
        }

        const userId = req.user.uid;

        // Firestore 'in' queries are limited to 30 items
        const chunks = [];
        for (let i = 0; i < postIds.length; i += 30) {
            chunks.push(postIds.slice(i, i + 30));
        }

        const results = {};
        await Promise.all(chunks.map(async (chunk) => {
            const snapshot = await db.collection('likes')
                .where('userId', '==', userId)
                .where('postId', 'in', chunk)
                .get();

            snapshot.docs.forEach(doc => {
                results[doc.data().postId] = true;
            });
        }));

        // Fill in missing with false for clarity
        postIds.forEach(id => {
            if (!results[id]) results[id] = false;
        });

        return res.json({
            success: true,
            data: results,
            error: null
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * @route   GET /api/interactions/likes/check
 * @desc    Check if current user liked a post and get canonical likeCount
 */
router.get('/likes/check', authenticate, async (req, res, next) => {
    try {
        const { postId } = req.query;
        if (!postId) return res.status(400).json({ error: 'postId query param required' });

        const userId = req.user.uid;
        const likeId = `${postId}_${userId}`;
        const [likeDoc, postDoc] = await Promise.all([
            db.collection('likes').doc(likeId).get(),
            db.collection('posts').doc(postId).get()
        ]);

        return res.json({
            success: true,
            data: {
                liked: likeDoc.exists,
                likeCount: postDoc.exists ? (postDoc.data().likeCount || 0) : 0
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/interactions/follows/check
 * @desc    Check if current user follows a target user
 */
router.get('/follows/check', authenticate, async (req, res, next) => {
    try {
        const { targetUserId } = req.query;
        if (!targetUserId) return res.status(400).json({ error: 'targetUserId query param required' });

        const userId = req.user.uid;
        const followId = `${userId}_${targetUserId}`;
        const followDoc = await db.collection('follows').doc(followId).get();

        return res.json({
            success: true,
            data: { followed: followDoc.exists },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/interactions/events/check
 * @desc    Check if current user is attending an event
 */
router.get('/events/check', authenticate, async (req, res, next) => {
    try {
        const { eventId } = req.query;
        if (!eventId) return res.status(400).json({ error: 'eventId query param required' });

        const userId = req.user.uid;
        const attendanceId = `${eventId}_${userId}`;
        const attendanceDoc = await db.collection('event_attendance').doc(attendanceId).get();

        return res.json({
            success: true,
            data: { attending: attendanceDoc.exists },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

export default router;

