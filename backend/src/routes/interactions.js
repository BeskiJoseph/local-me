import express from 'express';
import admin, { db } from '../config/firebase.js';
import geoIndex from '../services/geoIndex.js';
import logger from '../utils/logger.js';
import authenticate from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import { body, validationResult } from 'express-validator';
import { cleanPayload } from '../utils/sanitizer.js';
import { enforceLikeVelocity, enforceFollowVelocity } from '../middleware/interactionVelocity.js';
import { buildDisplayName } from '../utils/userDisplayName.js';
import { updateUserContextCache, getUserContext } from '../services/userContextService.js';
import { invalidateFeedCache } from './posts.js';
import { broadcastLikeUpdate, broadcastCommentUpdate } from '../services/socketService.js';
import NotificationService from '../services/notificationService.js';
import { filterContent } from '../utils/contentFilter.js';

const router = express.Router();

function resolveActorDisplayName(req) {
    return buildDisplayName({
        displayName: req.user?.displayName,
        email: req.user?.email,
        fallback: 'User'
    });
}

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
    enforceLikeVelocity,
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

        const cleanBody = cleanPayload(req.body, ['postId']);
        const { postId } = cleanBody;
        const userId = req.user.uid;
        const actorDisplayName = resolveActorDisplayName(req);
        const likeId = `${postId}_${userId}`;
        const likeRef = db.collection('likes').doc(likeId);
        const postRef = db.collection('posts').doc(postId);

        let notificationPayload = null;
        let wasLiked = false;
        try {
            await db.runTransaction(async (transaction) => {
                const [likeDoc, postDoc] = await Promise.all([
                    transaction.get(likeRef),
                    transaction.get(postRef)
                ]);

                if (!postDoc.exists) throw new Error('Post not found');

                if (likeDoc.exists) {
                    // Unlike
                    transaction.delete(likeRef);
                    const currentScore = postDoc.data().engagementScore || 0;
                    transaction.update(postRef, {
                        likeCount: admin.firestore.FieldValue.increment(-1),
                        engagementScore: Math.max(0, currentScore - 5)
                    });
                } else {
                    // Like
                    transaction.set(likeRef, {
                        postId,
                        userId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    transaction.update(postRef, {
                        likeCount: admin.firestore.FieldValue.increment(1),
                        engagementScore: admin.firestore.FieldValue.increment(5)
                    });

                    // Prepare notification to post author if different from liker
                    if (postDoc.data().authorId !== userId) {
                        notificationPayload = {
                            toUserId: postDoc.data().authorId,
                            fromUserId: userId,
                            fromUserName: actorDisplayName,
                            fromUserProfileImage: req.user.photoURL,
                            type: 'like',
                            postId,
                            postThumbnail: postDoc.data().thumbnailUrl || postDoc.data().mediaUrl
                        };
                    }
                }
                wasLiked = likeDoc.exists;
                // Calculate new count for real-time broadcast
                const currentCount = postDoc.data().likeCount || 0;
                const newCount = Math.max(0, currentCount + (wasLiked ? -1 : 1));

                // Broadcast to other users via WebSocket (Batched 2s)
                broadcastLikeUpdate(postId, newCount, userId);
            });

            // Trigger notification outside transaction for speed
            if (notificationPayload) {
                NotificationService.notify(notificationPayload.toUserId, notificationPayload)
                    .catch(err => logger.error('Like Notification Error', { err: err.message }));
            }

            // Optimistically update the feed context for this user
            updateUserContextCache(userId, postId, wasLiked ? 'unlike' : 'like');

            // Log Audit Action after successful transaction
            // Log Audit Action in background (Async)
            AuditService.logAction({
                userId,
                action: 'POST_LIKE_TOGGLE',
                metadata: { postId },
                req
            }).catch(e => logger.error('Audit Log Error', e));

            return res.json({
                success: true,
                data: { status: 'active' },
                error: null
            });
        } catch (error) {
            logger.error('Like Error', { error: error.message, postId, userId });
            return res.status(500).json({ error: 'An internal error occurred' });
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
        const cleanBody = cleanPayload(req.body, ['postId', 'text', 'parentId']);
        const { postId, text, parentId } = cleanBody;

        // 1. YouTube-style Spam Filter
        if (!filterContent(text)) {
            return res.status(400).json({
                success: false,
                error: 'Your comment was flagged by our spam filter.'
            });
        }
        const userId = req.user.uid;
        const actorDisplayName = resolveActorDisplayName(req);
        const postRef = db.collection('posts').doc(postId);
        const commentRef = db.collection('comments').doc();

        let notificationPayload = null;
        try {
            await db.runTransaction(async (transaction) => {
                const postDoc = await transaction.get(postRef);
                if (!postDoc.exists) throw new Error('Post not found');

                const commentData = {
                    postId,
                    userId,
                    authorId: userId,
                    authorName: actorDisplayName,
                    authorProfileImage: req.user.photoURL,
                    text: text.substring(0, 1000), // Max length
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    likeCount: 0,
                    replyCount: 0,
                    parentId: parentId || null // Explicit null for indexing
                };

                if (parentId) {
                    const parentRef = db.collection('comments').doc(parentId);
                    transaction.update(parentRef, {
                        replyCount: admin.firestore.FieldValue.increment(1)
                    });
                }

                transaction.set(commentRef, commentData);

                transaction.update(postRef, {
                    commentCount: admin.firestore.FieldValue.increment(1),
                    engagementScore: admin.firestore.FieldValue.increment(10)
                });

                // Broadcast to other users in real-time
                const currentCount = postDoc.data().commentCount || 0;
                broadcastCommentUpdate(postId, currentCount + 1, {
                    id: commentRef.id,
                    text: text.substring(0, 1000),
                    authorId: userId,
                    authorName: actorDisplayName,
                    authorProfileImage: req.user.photoURL,
                    createdAt: new Date().toISOString(),
                    postId
                });

                // Prepare notification to post author if different from commenter
                if (postDoc.data().authorId !== userId) {
                    notificationPayload = {
                        toUserId: postDoc.data().authorId,
                        fromUserId: userId,
                        fromUserName: actorDisplayName,
                        fromUserProfileImage: req.user.photoURL,
                        type: 'comment',
                        postId,
                        commentText: text,
                        postThumbnail: postDoc.data().thumbnailUrl || postDoc.data().mediaUrl
                    };
                }
            });


            // Trigger notification outside transaction
            if (notificationPayload) {
                NotificationService.notify(notificationPayload.toUserId, notificationPayload)
                    .catch(err => logger.error('Comment Notification Error', { err: err.message }));
            }

            // Mentions logic
            _processMentions(text, userId).then(mentionUids => {
                mentionUids.forEach(targetUid => {
                    // Don't send mention if they already got a comment notification
                    if (notificationPayload && targetUid === notificationPayload.toUserId) return;

                    NotificationService.notify(targetUid, {
                        toUserId: targetUid,
                        fromUserId: userId,
                        fromUserName: actorDisplayName,
                        fromUserProfileImage: req.user.photoURL,
                        type: 'mention',
                        postId,
                        commentText: text
                    }).catch(err => logger.error('Mention Notification Error', { err: err.message }));
                });
            });

            // Log Audit Action after successful transaction
            // Log Audit Action in background
            AuditService.logAction({
                userId,
                action: 'POST_COMMENT_CREATED',
                metadata: { postId, commentId: commentRef.id },
                req
            }).catch(e => logger.error('Audit Log Error', e));

            return res.json({
                success: true,
                data: {
                    id: commentRef.id,
                    text: text.substring(0, 1000),
                    authorId: userId,
                    authorName: actorDisplayName,
                    authorProfileImage: req.user.photoURL,
                    createdAt: new Date().toISOString(),
                    postId,
                    likeCount: 0,
                    replyCount: 0,
                    parentId: parentId || null
                }
            });
        } catch (err) {
            logger.error('Comment implementation error', { error: err.message, stack: err.stack });
            return res.status(500).json({ success: false, error: 'Failed to post comment' });
        }
    }
);

/**
 * @route   DELETE /api/interactions/comment/:commentId
 * @desc    Delete a comment and decrement counts
 */
router.delete(
    '/comment/:commentId',
    async (req, res) => {
        const { commentId } = req.params;
        const userId = req.user.uid;

        try {
            const commentRef = db.collection('comments').doc(commentId);
            
            await db.runTransaction(async (transaction) => {
                const commentDoc = await transaction.get(commentRef);
                if (!commentDoc.exists) throw new Error('Comment not found');

                const commentData = commentDoc.data();
                
                // Permission Check: only author can delete
                if (commentData.userId !== userId && commentData.authorId !== userId) {
                    throw new Error('Unauthorized to delete this comment');
                }

                const postRef = db.collection('posts').doc(commentData.postId);

                // 1. Decrement post comment count
                transaction.update(postRef, {
                    commentCount: admin.firestore.FieldValue.increment(-1)
                });

                // 2. If it's a reply, decrement parent reply count
                if (commentData.parentId) {
                    const parentRef = db.collection('comments').doc(commentData.parentId);
                    transaction.update(parentRef, {
                        replyCount: admin.firestore.FieldValue.increment(-1)
                    });
                }

                // 3. Delete the comment itself
                transaction.delete(commentRef);

                // Log Audit Action in transaction scope (optional but good)
                AuditService.logAction({
                    userId,
                    action: 'POST_COMMENT_DELETED',
                    metadata: { postId: commentData.postId, commentId },
                    req
                }).catch(e => logger.error('Audit Log Error (Delete)', e));
            });

            return res.json({ success: true, message: 'Comment deleted successfully' });
        } catch (err) {
            logger.error('Comment deletion error', { error: err.message, userId });
            const status = err.message === 'Unauthorized to delete this comment' ? 403 : 500;
            return res.status(status).json({ success: false, error: err.message });
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
    enforceFollowVelocity,
    async (req, res) => {
        const cleanBody = cleanPayload(req.body, ['targetUserId']);
        const { targetUserId } = cleanBody;
        const userId = req.user.uid;
        const actorDisplayName = resolveActorDisplayName(req);
        if (userId === targetUserId) {
            return res.status(400).json({ error: 'You cannot follow yourself' });
        }

        const followId = `${userId}_${targetUserId}`;
        const followRef = db.collection('follows').doc(followId);
        const currentUserRef = db.collection('users').doc(userId);
        const targetUserRef = db.collection('users').doc(targetUserId);

        let wasFollowing = false;
        try {
            await db.runTransaction(async (transaction) => {
                const [followDoc, targetUserDoc] = await Promise.all([
                    transaction.get(followRef),
                    transaction.get(targetUserRef)
                ]);

                if (!targetUserDoc.exists) {
                    throw new Error('Target user does not exist');
                }

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
                        followerId: userId, // Immutable: Enforced to be the request user
                        followingId: targetUserId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    transaction.update(currentUserRef, {
                        followingCount: admin.firestore.FieldValue.increment(1)
                    });
                    transaction.update(targetUserRef, {
                        subscribers: admin.firestore.FieldValue.increment(1)
                    });

                    NotificationService.notify(targetUserId, {
                        toUserId: targetUserId,
                        fromUserId: userId,
                        fromUserName: actorDisplayName,
                        fromUserProfileImage: req.user.photoURL,
                        type: 'follow'
                    }).catch(err => logger.error('Notification Error', { err: err.message }));
                }
                wasFollowing = followDoc.exists;
            });
            // Optimistically update the context for this user so they see the switch instantly
            updateUserContextCache(userId, targetUserId, wasFollowing ? 'unfollow' : 'follow');

            return res.json({
                success: true,
                data: { status: 'active' },
                error: null
            });
        } catch (error) {
            return res.status(500).json({ error: 'An internal error occurred' });
        }
    }
);

/**
 * @route   POST /api/interactions/event/join
 * @desc    Join or leave an event (Group Membership + RSVP combo)
 */
router.post(
    '/event/join',
    [
        body('eventId').notEmpty(),
    ],
    async (req, res) => {
        const cleanBody = cleanPayload(req.body, ['eventId']);
        const { eventId } = cleanBody;
        const userId = req.user.uid;

        const eventRef = db.collection('posts').doc(eventId);

        // Deterministic IDs for duplicate prevention across both tracking systems
        const attendanceId = `${eventId}_${userId}`;
        const attendanceRef = db.collection('event_attendance').doc(attendanceId);

        const groupMemberRef = db.collection('event_group_members').doc(attendanceId);

        try {
            await db.runTransaction(async (transaction) => {
                const [eventDoc, attendanceDoc] = await Promise.all([
                    transaction.get(eventRef),
                    transaction.get(attendanceRef)
                ]);

                if (!eventDoc.exists) throw new Error('Event not found');

                // Extra safeguard: Only join active events
                const data = eventDoc.data();
                if (data.eventEndDate && new Date(data.eventEndDate) < new Date()) {
                    throw new Error('Cannot join an archived or expired event');
                }

                if (attendanceDoc.exists) {
                    // Leave Event actions
                    transaction.delete(attendanceRef);
                    transaction.delete(groupMemberRef); // Keeps systems mirrored identically

                    transaction.update(eventRef, {
                        attendeeCount: admin.firestore.FieldValue.increment(-1)
                    });
                } else {
                    // Join Event actions
                    transaction.set(attendanceRef, {
                        eventId,
                        userId,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });

                    transaction.set(groupMemberRef, {
                        eventId,
                        userId,
                        role: 'member',
                        joinedAt: admin.firestore.FieldValue.serverTimestamp()
                    });

                    transaction.update(eventRef, {
                        attendeeCount: admin.firestore.FieldValue.increment(1)
                    });

                    // Send notification to event creator
                    const eventData = eventDoc.data();
                    if (eventData.authorId && eventData.authorId !== userId) {
                        NotificationService.notify(eventData.authorId, {
                            toUserId: eventData.authorId,
                            fromUserId: userId,
                            fromUserName: resolveActorDisplayName(req),
                            type: 'event_join',
                            postId: eventId,
                            postThumbnail: eventData.thumbnailUrl || eventData.mediaUrl
                        }).catch(err => logger.error('Event Join Notification Error', { err: err.message }));
                    }
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
 * Extracts mentions from text and returns unique list of mentioned uids
 */
async function _processMentions(text, currentUserId) {
    if (!text) return [];
    const mentionRegex = /@([a-zA-Z0-9._]+)/g;
    const matches = [...text.matchAll(mentionRegex)];
    if (matches.length === 0) return [];

    const usernames = [...new Set(matches.map(m => m[1].toLowerCase()))];
    const mentionUids = [];

    // Chunk username lookups to avoid massive IN clauses
    for (let i = 0; i < usernames.length; i += 10) {
        const chunk = usernames.slice(i, i + 10);
        const userSnapshot = await db.collection('users')
            .where('username', 'in', chunk)
            .limit(10)
            .get();

        userSnapshot.docs.forEach(doc => {
            const uid = doc.id;
            if (uid !== currentUserId) {
                mentionUids.push(uid);
            }
        });
    }

    return [...new Set(mentionUids)];
}

/**
 * @route   GET /api/interactions/comments/:postId
 * @desc    Get comments for a post (Cursor-based Pagination)
 */
router.get('/comments/:postId', authenticate, async (req, res, next) => {
    try {
        const { limit = 20, afterId, sort = 'newest' } = req.query;
        const userId = req.user.uid;

        let query = db.collection('comments')
            .where('postId', '==', req.params.postId)
            .where('parentId', '==', null); // Top-level only

        // Sorting: 'top' (likes) or 'newest' (timestamp)
        if (sort === 'top') {
            query = query.orderBy('likeCount', 'desc').orderBy('createdAt', 'desc');
        } else {
            query = query.orderBy('createdAt', 'desc');
        }

        if (afterId) {
            const lastDoc = await db.collection('comments').doc(afterId).get();
            if (lastDoc.exists) {
                query = query.startAfter(lastDoc);
            }
        }

        const snapshot = await query.limit(parseInt(limit)).get();

        // Batch check which comments the user has liked
        const commentIds = snapshot.docs.map(doc => doc.id);
        const likedSet = new Set();
        if (commentIds.length > 0) {
            // Firestore 'in' query supports up to 30 items
            const likesSnapshot = await db.collection('comment_likes')
                .where('userId', '==', userId)
                .where('commentId', 'in', commentIds.slice(0, 30))
                .get();
            likesSnapshot.docs.forEach(doc => likedSet.add(doc.data().commentId));
        }

        const comments = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
                id: doc.id,
                ...data,
                parentId: data.parentId || null,
                isLiked: likedSet.has(doc.id),
                createdAt: safeDate(data.createdAt).toISOString()
            };
        });

        return res.json({
            success: true,
            data: comments,
            pagination: {
                cursor: comments.length === parseInt(limit) ? comments[comments.length - 1].id : null,
                hasMore: comments.length === parseInt(limit)
            }
        });
    } catch (err) {
        console.error("🔥 COMMENTS ERROR [GET /comments/:postId]:", err);
        return res.status(500).json({
            success: false,
            error: err.message,
            stack: err.stack,
            requestId: req.params.postId
        });
    }
});

/**
 * @route   GET /api/interactions/comments/:commentId/replies
 * @desc    Load replies for a specific top-level comment
 */
router.get('/comments/:commentId/replies', authenticate, async (req, res, next) => {
    try {
        const { limit = 10, afterId } = req.query;
        let query = db.collection('comments')
            .where('parentId', '==', req.params.commentId)
            .orderBy('createdAt', 'asc');

        if (afterId) {
            const lastDoc = await db.collection('comments').doc(afterId).get();
            if (lastDoc.exists) query = query.startAfter(lastDoc);
        }

        const snapshot = await query.limit(parseInt(limit)).get();
        const replies = snapshot.docs.map(doc => {
            const data = doc.data();
            return {
                id: doc.id,
                ...data,
                parentId: data.parentId || null,
                createdAt: safeDate(data.createdAt).toISOString()
            };
        });

        return res.json({
            success: true,
            data: replies,
            pagination: {
                cursor: replies.length === parseInt(limit) ? replies[replies.length - 1].id : null,
                hasMore: replies.length === parseInt(limit)
            }
        });
    } catch (err) {
        console.error("🔥 REPLIES ERROR [GET /comments/:commentId/replies]:", err);
        return res.status(500).json({
            success: false,
            error: err.message,
            stack: err.stack,
            requestId: req.params.commentId
        });
    }
});

/**
 * @route   POST /api/interactions/comments/:commentId/like
 * @desc    Toggle like on a comment
 */
router.post('/comments/:commentId/like', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.uid;
        const commentId = req.params.commentId;
        const likeRef = db.collection('comment_likes').doc(`${commentId}_${userId}`);
        const commentRef = db.collection('comments').doc(commentId);

        let isLiked = false;
        await db.runTransaction(async (transaction) => {
            const likeDoc = await transaction.get(likeRef);
            if (likeDoc.exists) {
                transaction.delete(likeRef);
                transaction.update(commentRef, { likeCount: admin.firestore.FieldValue.increment(-1) });
                isLiked = false;
            } else {
                transaction.set(likeRef, { userId, commentId, createdAt: admin.firestore.FieldValue.serverTimestamp() });
                transaction.update(commentRef, { likeCount: admin.firestore.FieldValue.increment(1) });
                isLiked = true;
            }
        });

        return res.json({ success: true, data: { isLiked } });
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

        // 1. Safe handling for empty or malformed list
        if (!postIds || !Array.isArray(postIds) || postIds.length === 0) {
            return res.json({ success: true, data: {}, error: null });
        }

        const userId = req.user.uid;

        // 2. Firestore 'in' queries are limited to 30 items
        const chunks = [];
        for (let i = 0; i < postIds.length; i += 30) {
            chunks.push(postIds.slice(i, i + 30));
        }

        // Use Object.create(null) to avoid prototype pollution
        const results = Object.create(null);

        await Promise.all(chunks.map(async (chunk) => {
            const snapshot = await db.collection('likes')
                .where('userId', '==', userId)
                .where('postId', 'in', chunk)
                .get();

            snapshot.docs.forEach(doc => {
                results[doc.data().postId] = true;
            });
        }));

        // 3. Always return all requested IDs, defaulting to false for clarity
        postIds.forEach(id => {
            if (results[id] === undefined) results[id] = false;
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

        // Use cached/optimistic 'isLiked' state from memory
        const { likedPostIds } = await getUserContext(userId, [postId]);
        const liked = likedPostIds.has(postId);

        // Fetch fresh likeCount from DB
        const postDoc = await db.collection('posts').doc(postId).get();

        return res.json({
            success: true,
            data: {
                liked: liked,
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

        // Use cached/optimistic user context for follows too
        const { followedUserIds } = await getUserContext(userId);

        return res.json({
            success: true,
            data: followedUserIds.has(targetUserId), // Response is just bool in BackendClient
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

/**
 * @route   GET /api/interactions/events/my-events
 * @desc    Returns list of event IDs the current user has joined
 */
router.get('/events/my-events', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.uid;

        const memberSnap = await db.collection('event_group_members')
            .where('userId', '==', userId)
            .get();

        const eventIds = memberSnap.docs.map(doc => doc.data().eventId);

        return res.json({
            success: true,
            data: { eventIds },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

export default router;

