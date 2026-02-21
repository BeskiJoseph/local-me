import express from 'express';
import Joi from 'joi';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import logger from '../utils/logger.js';
import admin from 'firebase-admin';

const router = express.Router();

// Joi Schema for Post Creation
const postSchema = Joi.object({
    title: Joi.string().max(200).allow(null, ''),
    body: Joi.string().max(2000).allow(null, ''),
    text: Joi.string().max(2000).allow(null, ''),
    category: Joi.string().max(50).allow(null, ''),
    city: Joi.string().max(100).allow(null, ''),
    country: Joi.string().max(100).allow(null, ''),
    mediaUrl: Joi.string().uri().allow(null, ''),
    mediaType: Joi.string().valid('image', 'video', 'none').default('none'),
    thumbnailUrl: Joi.string().uri().allow(null, ''),
    location: Joi.object({
        lat: Joi.number(),
        lng: Joi.number(),
        name: Joi.string()
    }).allow(null).optional(),
    tags: Joi.array().items(Joi.string().max(30)).max(10).allow(null).optional(),
    isEvent: Joi.boolean().default(false),
    eventDate: Joi.date().iso().allow(null).optional(),
    eventLocation: Joi.string().max(200).allow(null).optional(),
    isFree: Joi.boolean().default(true),
    eventType: Joi.string().max(50).allow(null).optional(),
    subtitle: Joi.string().max(500).allow(null, '').optional()
}).or('text', 'mediaUrl', 'title')
    .unknown(true); // Allow extra fields like 'id' or 'authorId' common in Flutter for stability

/**
 * @route   POST /api/posts
 * @desc    Create a new post with enterprise safety checks
 */
router.post('/', authenticate, async (req, res, next) => {
    logger.debug({ body: req.body }, 'Incoming POST /api/posts request');
    try {
        // 1. Validate Input
        const { error, value } = postSchema.validate(req.body);
        if (error) {
            const err = new Error(error.details[0].message);
            err.status = 400;
            err.code = 'post/invalid-input';
            return next(err);
        }

        const { uid } = req.user;

        // 2. account Age Check (Min 1 minute after signup)
        const userDoc = await db.collection('users').doc(uid).get();
        const userData = userDoc.data();

        const createdAt = userData?.createdAt?.toDate() || new Date(0);
        const ageInMs = Date.now() - createdAt.getTime();

        if (ageInMs < 60 * 1000) { // 1 minute
            const err = new Error('Your account is too new to post. Please wait a minute.');
            err.status = 403;
            err.code = 'post/account-too-new';
            return next(err);
        }

        // 3. Shadow Ban Implementation
        // bad actors can still post, but their posts aren't visible to others
        const isShadowBanned = req.user.status === 'shadow_banned';

        const postData = {
            ...value,
            authorId: uid,
            authorName: req.user.displayName,
            authorProfileImage: req.user.photoURL,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            likeCount: 0,
            commentCount: 0,
            visibility: isShadowBanned ? 'shadow' : 'public',
            status: 'active'
        };

        const postRef = await db.collection('posts').add(postData);

        // 4. Invalidate Feed Cache (Stage 3+ refinement)
        FEED_CACHE.clear();
        logger.debug({ userId: uid }, 'Feed cache invalidated after post creation');

        // 5. Audit Trail
        await AuditService.logAction({
            userId: uid,
            action: 'POST_CREATED',
            metadata: { postId: postRef.id, isShadow: isShadowBanned },
            req
        });

        logger.info({ postId: postRef.id, userId: uid }, 'Post created successfully');

        return res.status(201).json({
            success: true,
            data: {
                id: postRef.id,
                ...postData,
                createdAt: new Date().toISOString()
            },
            error: null
        });

    } catch (err) {
        next(err);
    }
});

// Simple In-Memory Cache for Feed (V1)
const FEED_CACHE = new Map();
const CACHE_TTL = 30 * 1000; // 30 seconds

/**
 * @route   GET /api/posts/feed
 * @desc    Get paginated feed with cursor validation
 */
router.get('/feed', authenticate, async (req, res, next) => {
    try {
        const { cursor, limit = 10, type = 'discovery' } = req.query;
        const pageSize = Math.min(parseInt(limit), 50);
        const { uid } = req.user;

        // 0. Cache Check
        // For first page (no cursor): key = type only → shared across all users, instant tab switch
        // For paginated pages: key includes cursor for correctness
        const cacheKey = cursor
            ? `${uid}:${type}:${cursor}:${pageSize}`
            : `feed:${type}:${pageSize}`;
        const cached = FEED_CACHE.get(cacheKey);
        if (cached && (Date.now() - cached.timestamp < CACHE_TTL)) {
            logger.debug({ uid, cacheKey }, 'Serving feed from in-memory cache');
            return res.json(cached.data);
        }

        // 1. Fetch User Interests (Top 5)
        // Wrapped in try/catch: if the userId+score composite index isn't built yet,
        // fall back to empty interests → discovery feed instead of 500.
        let topInterests = [];
        try {
            const interestsSnapshot = await db.collection('user_interests')
                .where('userId', '==', uid)
                .orderBy('score', 'desc')
                .limit(5)
                .get();
            topInterests = interestsSnapshot.docs.map(doc => doc.data().tag);
        } catch (interestErr) {
            logger.warn({ uid, err: interestErr.message }, 'user_interests query failed, falling back to discovery');
            // topInterests stays [] → discovery feed path below
        }

        // 2. Query Blending Logic (Simplified for Backend)
        let query;
        if (topInterests.length > 0 && type === 'personalized') {
            // Priority 1: Interests
            query = db.collection('posts')
                .where('category', 'in', topInterests)
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .orderBy('createdAt', 'desc');
        } else {
            // Global Discovery (Trending/Recent Mix)
            query = db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .orderBy('createdAt', 'desc');
        }

        // 3. Cursor Validation
        if (cursor) {
            const startAfterDoc = await db.collection('posts').doc(cursor).get();
            if (startAfterDoc.exists) {
                query = query.startAfter(startAfterDoc);
            }
        }

        let snapshot;
        try {
            snapshot = await query.limit(pageSize).get();
        } catch (indexErr) {
            // FAILED_PRECONDITION = composite index not yet built in Firebase Console
            // Gracefully fall back to simple discovery query
            if (indexErr.code === 9 || indexErr.message?.includes('index')) {
                logger.warn({ type, topInterests }, 'Composite index missing, falling back to discovery query');
                const fallbackQuery = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active')
                    .orderBy('createdAt', 'desc')
                    .limit(pageSize);
                snapshot = await fallbackQuery.get();
            } else {
                throw indexErr;
            }
        }

        // 4. Mapping
        const posts = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
            createdAt: doc.data().createdAt?.toDate()?.toISOString()
        }));

        // 5. Discovery Fallback: If current pool is empty, provide global discovery
        if (posts.length === 0 && topInterests.length > 0) {
            // ... would repeat with global query ...
            // (Simplified for now: frontend will handle Empty State or request Discovery)
        }

        const lastDoc = snapshot.docs[snapshot.docs.length - 1];

        const responseData = {
            success: true,
            data: posts,
            pagination: {
                cursor: lastDoc ? lastDoc.id : null,
                hasMore: posts.length === pageSize
            },
            error: null
        };

        // 6. Save to Cache
        FEED_CACHE.set(cacheKey, {
            timestamp: Date.now(),
            data: responseData
        });

        // 7. Cleanup Cache (Prevent memory leaks)
        if (FEED_CACHE.size > 1000) {
            const oldestKey = FEED_CACHE.keys().next().value;
            FEED_CACHE.delete(oldestKey);
        }

        return res.json(responseData);

    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/posts/:id
 * @desc    Get a single post by ID
 */
router.get('/:id', authenticate, async (req, res, next) => {
    try {
        const doc = await db.collection('posts').doc(req.params.id).get();
        if (!doc.exists) {
            const err = new Error('Post not found');
            err.status = 404;
            err.code = 'post/not-found';
            return next(err);
        }

        const data = doc.data();
        // Privacy check
        if (data.visibility === 'shadow' && data.authorId !== req.user.uid) {
            const err = new Error('Post not found'); // Stealth 404 for shadow banned posts
            err.status = 404;
            return next(err);
        }

        return res.json({
            success: true,
            data: {
                id: doc.id,
                ...data,
                createdAt: data.createdAt?.toDate()?.toISOString()
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   DELETE /api/posts/:id
 * @desc    Delete a post (Author or Admin only)
 */
router.delete('/:id', authenticate, async (req, res, next) => {
    try {
        const postRef = db.collection('posts').doc(req.params.id);
        const doc = await postRef.get();

        if (!doc.exists) return res.status(404).json({ error: 'Post not found' });

        const data = doc.data();
        if (data.authorId !== req.user.uid && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Unauthorized to delete this post' });
        }

        await postRef.delete();

        await AuditService.logAction({
            userId: req.user.uid,
            action: 'POST_DELETED',
            metadata: { postId: req.params.id },
            req
        });

        return res.json({
            success: true,
            data: { message: 'Post deleted' },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/posts
 * @desc    Get posts with filters (authorId, category, city)
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const { authorId, category, city, limit = 20, afterId } = req.query;
        let query = db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active');

        if (authorId) query = query.where('authorId', '==', authorId);
        if (category) query = query.where('category', '==', category);
        if (city) query = query.where('city', '==', city);

        query = query.orderBy('createdAt', 'desc');

        if (afterId) {
            const lastDoc = await db.collection('posts').doc(afterId).get();
            if (lastDoc.exists) {
                query = query.startAfter(lastDoc);
            }
        }

        query = query.limit(Math.min(parseInt(limit), 100));

        let snapshot;
        try {
            snapshot = await query.get();
        } catch (indexErr) {
            if (indexErr.code === 9 || indexErr.message?.includes('index')) {
                // If specific filters are used (Profile, Category, City), we MUST NOT fallback to global feed
                // This prevents "Data Leakage" where a user's profile shows everyone's posts.
                if (authorId || category || city) {
                    logger.warn({ authorId, category, city }, 'Composite index missing for filtered query. Filtered results will be unavailable until indexing completes.');
                    return res.json({
                        success: true,
                        data: [],
                        pagination: { cursor: null, hasMore: false },
                        message: 'Filtered results are currently being indexed by Firestore. Your profile posts will appear here once the index is ready.'
                    });
                }

                logger.warn('Composite index missing for general feed, using basic fallback');
                const fallbackQuery = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active')
                    .orderBy('createdAt', 'desc')
                    .limit(Math.min(parseInt(limit), 100));
                snapshot = await fallbackQuery.get();
            } else {
                throw indexErr;
            }
        }

        const posts = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
            createdAt: doc.data().createdAt?.toDate()?.toISOString()
        }));

        return res.json({
            success: true,
            data: posts,
            error: null
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * @route   POST /api/posts/:id/messages
 * @desc    Send a chat message for an event/post
 */
router.post('/:id/messages', authenticate, async (req, res, next) => {
    try {
        const { text } = req.body;
        if (!text) return res.status(400).json({ error: 'Message text is required' });

        const messageData = {
            senderId: req.user.uid,
            senderName: req.user.displayName,
            senderProfileImage: req.user.photoURL,
            text,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

        const messageRef = await db.collection('posts')
            .doc(req.params.id)
            .collection('messages')
            .add(messageData);

        return res.status(201).json({
            success: true,
            data: { id: messageRef.id, ...messageData },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/posts/:id/messages
 * @desc    Get chat messages for an event/post
 */
router.get('/:id/messages', authenticate, async (req, res, next) => {
    try {
        const snapshot = await db.collection('posts')
            .doc(req.params.id)
            .collection('messages')
            .orderBy('timestamp', 'desc')
            .limit(100)
            .get();

        const messages = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
            timestamp: doc.data().timestamp?.toDate()?.toISOString()
        }));

        return res.json({
            success: true,
            data: messages,
            error: null
        });
    } catch (err) {
        next(err);
    }
});

export default router;
