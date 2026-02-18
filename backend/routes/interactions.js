import express from 'express';
import admin from 'firebase-admin';
import logger from '../utils/logger.js';
import { verifyFirebaseToken } from '../middleware/auth.js';
import { body, validationResult } from 'express-validator';

const router = express.Router();
const db = admin.firestore();

// Apply auth middleware to all interaction routes
router.use(verifyFirebaseToken);

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

            res.json({ success: true });
        } catch (error) {
            logger.error('Like Error', { error: error.message, postId, userId });
            res.status(500).json({ error: error.message });
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

            res.json({ success: true, commentId: commentRef.id });
        } catch (error) {
            res.status(500).json({ error: error.message });
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
            res.json({ success: true });
        } catch (error) {
            res.status(500).json({ error: error.message });
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
            res.json({ success: true });
        } catch (error) {
            res.status(500).json({ error: error.message });
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

export default router;
