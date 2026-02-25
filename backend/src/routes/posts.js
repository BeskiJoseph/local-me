import express from 'express';
import Joi from 'joi';
import { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';
import AuditService from '../services/auditService.js';
import logger from '../utils/logger.js';
import admin from 'firebase-admin';
import ngeohash from 'ngeohash';
import { cleanPayload } from '../utils/sanitizer.js';
import { buildDisplayName } from '../utils/userDisplayName.js';

const router = express.Router();

/**
 * Haversine Distance Formula (km)
 */
function getDistance(lat1, lon1, lat2, lon2) {
    if (!lat1 || !lon1 || !lat2 || !lon2) return 999999;
    const R = 6371; // Radius of the earth in km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

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
    eventStartDate: Joi.date().iso().allow(null).optional(),
    eventEndDate: Joi.date().iso().allow(null).optional(),
    eventDate: Joi.date().iso().allow(null).optional(), // Legacy fallback
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
    logger.debug({ body: Object.keys(req.body) }, 'Incoming POST /api/posts request');
    try {
        // Enforce strict allow-list for Mass Assignment Defense + Deep XSS sanitization
        const ALLOWED_POST_FIELDS = [
            'title', 'body', 'text', 'category', 'city', 'country',
            'mediaUrl', 'mediaType', 'thumbnailUrl', 'location',
            'tags', 'isEvent', 'eventStartDate', 'eventEndDate', 'eventDate',
            'eventLocation', 'isFree', 'eventType', 'subtitle', 'id', 'authorId'
        ];
        const cleanBody = cleanPayload(req.body, ALLOWED_POST_FIELDS);

        const { error, value } = postSchema.validate(cleanBody);
        if (error) {
            const err = new Error(error.details[0].message);
            err.status = 400;
            err.code = 'post/invalid-input';
            return next(err);
        }

        if (value.isEvent) {
            if (!value.eventStartDate || !value.eventEndDate) {
                const err = new Error('eventStartDate and eventEndDate are required when isEvent is true');
                err.status = 400;
                err.code = 'post/missing-event-dates';
                return next(err);
            }
            if (new Date(value.eventEndDate) <= new Date(value.eventStartDate)) {
                const err = new Error('eventEndDate must be strictly after eventStartDate');
                err.status = 400;
                err.code = 'post/invalid-event-dates';
                return next(err);
            }
        }

        const { uid } = req.user;

        // 2. account Age Check (Min 1 minute after signup)
        const userDoc = await db.collection('users').doc(uid).get();
        const userData = userDoc.data();
        const rawCreatedAt = userData?.createdAt;
        let createdAt;
        if (rawCreatedAt && typeof rawCreatedAt.toDate === 'function') {
            createdAt = rawCreatedAt.toDate();
        } else if (rawCreatedAt) {
            createdAt = new Date(rawCreatedAt);
        } else {
            createdAt = new Date(0);
        }

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
        const actorDisplayName = buildDisplayName({
            displayName: req.user.displayName,
            username: userData?.username,
            firstName: userData?.firstName,
            lastName: userData?.lastName,
            email: userData?.email || req.user.email,
            fallback: 'User'
        });

        // ∩┐╜∩┐╜∩┐╜ Geohash Calculation (Step 1) ∩┐╜∩┐╜∩┐╜
        let geoHash = null;
        if (value.location?.lat && value.location?.lng) {
            geoHash = ngeohash.encode(value.location.lat, value.location.lng, 5); // precision 5 (~5km)
        }

        const postData = {
            ...value,
            authorId: uid,
            authorName: actorDisplayName,
            authorProfileImage: req.user.photoURL,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            likeCount: 0,
            commentCount: 0,
            visibility: isShadowBanned ? 'shadow' : 'public',
            status: 'active',
            geoHash: geoHash
        };

        const postRef = db.collection('posts').doc(value.id || db.collection('posts').doc().id);

        await db.runTransaction(async (transaction) => {
            // 1. Create the post
            transaction.set(postRef, postData);

            // 2. If it is an event, create the governance group and initial admin member
            if (value.isEvent) {
                const groupRef = db.collection('event_groups').doc();
                transaction.set(groupRef, {
                    eventId: postRef.id,
                    creatorId: uid,
                    // If communityId exists in future, bind it here
                    groupStatus: 'active', // active | archived
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });

                const deterministicMemberId = `${postRef.id}_${uid}`;
                const memberRef = db.collection('event_group_members').doc(deterministicMemberId);
                transaction.set(memberRef, {
                    eventId: postRef.id,
                    userId: uid,
                    role: 'admin', // Creator is admin
                    joinedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        });

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
const FETCH_LOCKS = new Map();
const CACHE_TTL = 30 * 1000; // 30 seconds

/**
 * Safe Date Parsing Helper
 */
const safeParseIso = (val) => {
    if (!val) return null;
    try {
        if (typeof val.toDate === 'function') return val.toDate().toISOString();
        const dateObj = new Date(val);
        if (isNaN(dateObj.getTime())) return null;
        return dateObj.toISOString();
    } catch (e) { return null; }
};

/**
 * Helper to map Firestore doc to Post object
 */
const mapDocToPost = (doc) => {
    const d = doc.data();

    // Canonical event detection: explicit flag OR legacy category-based
    const isEvent = !!(d.isEvent || (d.category && d.category.toLowerCase() === 'events'));

    // Lazy mapping for Event dates & Status
    let eventStart = d.eventStartDate;
    let eventEnd = d.eventEndDate;
    let computedGroupStatus = 'active';

    if (isEvent) {
        eventStart = safeParseIso(eventStart);
        eventEnd = safeParseIso(eventEnd);
        let fallbackEventDate = safeParseIso(d.eventDate);

        // Fallback for missing dates (Legacy support without DB mutation)
        if (!eventStart && fallbackEventDate) {
            eventStart = fallbackEventDate;
        }
        if (!eventEnd && eventStart) {
            // Fallback to Start Date + 2 hours
            try {
                const startObj = new Date(eventStart);
                eventEnd = new Date(startObj.getTime() + (2 * 60 * 60 * 1000)).toISOString();
            } catch (e) { }
        }

        // Lazy Archival State (Compute only, NO WRITE)
        if (eventEnd) {
            try {
                if (new Date(eventEnd) < new Date()) {
                    computedGroupStatus = 'archived';
                }
            } catch (e) { }
        }
    }

    return {
        id: doc.id,
        title: d.title || '',
        body: d.body || d.text || '',
        mediaUrl: d.mediaUrl,
        mediaType: d.mediaType,
        thumbnailUrl: d.thumbnailUrl,
        authorId: d.authorId,
        authorName: d.authorName,
        authorProfileImage: d.authorProfileImage,
        likeCount: d.likeCount || 0,
        commentCount: d.commentCount || 0,
        isEvent: isEvent,
        eventStartDate: eventStart,
        eventEndDate: eventEnd,
        computedStatus: computedGroupStatus,
        createdAt: safeParseIso(d.createdAt),
        city: d.city,
        country: d.country,
        category: d.category || 'General',
        latitude: d.latitude || d.location?.lat,
        longitude: d.longitude || d.location?.lng,
        attendeeCount: d.attendeeCount || 0,
        geoHash: d.geoHash
    };
};

/**
 * Helper to embed like state into feed response
 */
async function embedLikeState(responseData, userId) {
    if (!responseData.data || responseData.data.length === 0) return responseData;

    const postIds = responseData.data.map(p => p.id);
    const likedIds = new Set();

    // Firestore 'in' limit is 30
    const chunks = [];
    for (let i = 0; i < postIds.length; i += 30) {
        chunks.push(postIds.slice(i, i + 30));
    }

    await Promise.all(chunks.map(async (chunk) => {
        const snapshot = await db.collection('likes')
            .where('userId', '==', userId)
            .where('postId', 'in', chunk)
            .get();
        snapshot.docs.forEach(doc => likedIds.add(doc.data().postId));
    }));

    const enrichedPosts = responseData.data.map(post => ({
        ...post,
        isLiked: likedIds.has(post.id)
    }));

    return {
        ...responseData,
        data: enrichedPosts
    };
}

/**
 * @route   GET /api/posts
 * @desc    Get paginated feed with cursor validation
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const { authorId, category, city, lat, lng, country, limit = 20, afterId } = req.query;
        logger.info({
            query: { lat, lng, category, city, country, afterId },
            user: { uid: req.user.uid, country: req.user.country }
        }, '[FEED_DEBUG] Fetching posts');
        const pageSize = Math.min(parseInt(limit), 50);
        const { uid } = req.user;

        // ∩┐╜∩┐╜∩┐╜ 1. GeoHash & Cache Check (Step 2 & 3) ∩┐╜∩┐╜∩┐╜
        let geoHash = null;
        if (lat && lng) {
            geoHash = ngeohash.encode(parseFloat(lat), parseFloat(lng), 5);
        }

        const cacheKey = geoHash
            ? `feed:${geoHash}:${pageSize}:${afterId || 'page1'}`
            : `feed:global:${pageSize}:${afterId || 'page1'}`;

        const cached = FEED_CACHE.get(cacheKey);
        let responseData;

        if (cached && (Date.now() - cached.timestamp < CACHE_TTL) && !authorId && !category && !city) {
            logger.debug({ geoHash, cacheKey }, 'Serving regional feed from in-memory cache');
            responseData = cached.data;
        } else {
            // ∩┐╜∩┐╜∩┐╜ 2. Promise Lock (Prevention of Dog-Piling) ∩┐╜∩┐╜∩┐╜
            if (FETCH_LOCKS.has(cacheKey) && !authorId && !category && !city) {
                logger.debug({ cacheKey }, 'Awaiting existing fetch lock for region');
                responseData = await FETCH_LOCKS.get(cacheKey);
            } else {
                // ∩┐╜∩┐╜∩┐╜ 3. Query Construction & Execution ∩┐╜∩┐╜∩┐╜
                const fetchPromise = (async () => {
                    // ∩┐╜∩┐╜∩┐╜ Progressive Multi-Ring Fetch (Local Feed Upgrade) ∩┐╜∩┐╜∩┐╜
                    // ∩┐╜∩┐╜∩┐╜ Progressive Multi-Ring Fetch (Local Feed Upgrade) ∩┐╜∩┐╜∩┐╜
                    if (lat && lng && !authorId && !category && !city && !afterId) {
                        logger.debug({ lat, lng }, 'Executing Multi-Ring expansion');
                        const results = [];
                        const seenIds = new Set();

                        const p6 = ngeohash.encode(parseFloat(lat), parseFloat(lng), 6);
                        const p5 = geoHash; // geoHash is already encoded with precision 5
                        const p4 = ngeohash.encode(parseFloat(lat), parseFloat(lng), 4);

                        const rings = [
                            { prefix: p6, label: 'hyper-local (~1km)' },
                            { prefix: p5, label: 'local (~5km)' },
                            { prefix: p4, label: 'regional (~40km)' }
                        ];

                        for (const ring of rings) {
                            const remaining = pageSize - results.length;
                            if (remaining <= 0) break;

                            logger.debug({ ring: ring.label, remaining }, 'Fetching ring');

                            try {
                                const snapshot = await db.collection('posts')
                                    .where('visibility', '==', 'public')
                                    .where('status', '==', 'active')
                                    .where('geoHash', '>=', ring.prefix)
                                    .where('geoHash', '<=', ring.prefix + '\uf8ff')
                                    .orderBy('geoHash')
                                    .orderBy('createdAt', 'desc')
                                    .limit(remaining)
                                    .get();

                                snapshot.docs.forEach(doc => {
                                    if (!seenIds.has(doc.id)) {
                                        seenIds.add(doc.id);
                                        results.push(mapDocToPost(doc));
                                    }
                                });
                            } catch (ringErr) {
                                // ... error handling ...
                            }
                        }
                        // Fallback 1: Global Trending (Fill gaps)
                        const remainingGaps = pageSize - results.length;
                        if (remainingGaps > 0) {
                            try {
                                const globalSnapshot = await db.collection('posts')
                                    .where('visibility', '==', 'public')
                                    .where('status', '==', 'active')
                                    .orderBy('createdAt', 'desc')
                                    .limit(remainingGaps)
                                    .get();

                                globalSnapshot.docs.forEach(doc => {
                                    if (!seenIds.has(doc.id)) {
                                        seenIds.add(doc.id);
                                        results.push(mapDocToPost(doc));
                                    }
                                });
                            } catch (globalErr) {
                                logger.error({ error: globalErr.message }, 'Global fallback failed');
                            }
                        }

                        return {
                            success: true,
                            data: results,
                            pagination: {
                                cursor: results.length > 0 ? results[results.length - 1].id : null,
                                hasMore: results.length === pageSize
                            }
                        };
                    }

                    // ∩┐╜∩┐╜∩┐╜ Default Single-Query Logic (Filtered or Paginated) ∩┐╜∩┐╜∩┐╜
                    let query = db.collection('posts')
                        .where('visibility', '==', 'public')
                        .where('status', '==', 'active');

                    if (authorId) query = query.where('authorId', '==', authorId);
                    if (category) query = query.where('category', '==', category);
                    if (city) query = query.where('city', '==', city);
                    if (geoHash && !authorId && !category && !city) {
                        query = query.where('geoHash', '==', geoHash);
                    }

                    query = query.orderBy('createdAt', 'desc');

                    if (afterId) {
                        const lastDoc = await db.collection('posts').doc(afterId).get();
                        if (lastDoc.exists) {
                            query = query.startAfter(lastDoc);
                        }
                    }

                    query = query.limit(pageSize);

                    let snapshot;
                    try {
                        snapshot = await query.get();
                    } catch (indexErr) {
                        if (indexErr.code === 9 || indexErr.message?.includes('index')) {
                            logger.error({ query: req.query }, 'Missing Firestore composite index for filtered query');
                            const error = new Error('Query misconfigured: missing composite index.');
                            error.status = 500;
                            throw error;
                        }
                        throw indexErr;
                    }

                    const posts = snapshot.docs.map(mapDocToPost);

                    return {
                        success: true,
                        data: posts,
                        pagination: {
                            cursor: snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1].id : null,
                            hasMore: posts.length === pageSize
                        }
                    };
                })();

                // Only lock shared regional feeds
                if (!authorId && !category && !city) {
                    FETCH_LOCKS.set(cacheKey, fetchPromise);
                }

                try {
                    responseData = await fetchPromise;

                    // ∩┐╜∩┐╜∩┐╜ 4. Cache Management ∩┐╜∩┐╜∩┐╜
                    if (!authorId && !category && !city) {
                        FEED_CACHE.set(cacheKey, {
                            timestamp: Date.now(),
                            data: responseData
                        });
                    }
                } finally {
                    FETCH_LOCKS.delete(cacheKey);
                }
            }
        }

        // ∩┐╜∩┐╜∩┐╜ 5. Embed Like State (Step 4) ∩┐╜∩┐╜∩┐╜
        const finalResponse = await embedLikeState(responseData, uid);

        // ∩┐╜∩┐╜∩┐╜ 6. Anti-Scraping Throttler (Layer 4) ∩┐╜∩┐╜∩┐╜
        // Adds 50-200ms of random jitter to feed requests to frustrate high-velocity scrapers
        // without visibly degrading UX.
        if (!afterId || afterId === 'page1') {
            await new Promise(resolve => setTimeout(resolve, Math.random() * 150 + 50));
        }

        return res.json(finalResponse);

    } catch (err) {
        return next(err);
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

        // Check if liked by current user
        const likeDoc = await db.collection('likes')
            .where('userId', '==', req.user.uid)
            .where('postId', '==', req.params.id)
            .limit(1)
            .get();

        // Perform same lazy logic as mapped feed
        let eventStart = data.eventStartDate;
        let eventEnd = data.eventEndDate;
        let computedGroupStatus = 'active';

        if (data.isEvent) {
            eventStart = safeParseIso(eventStart);
            eventEnd = safeParseIso(eventEnd);
            let fallbackEventDate = safeParseIso(data.eventDate);

            if (!eventStart && fallbackEventDate) eventStart = fallbackEventDate;

            if (!eventEnd && eventStart) {
                try {
                    const sObj = new Date(eventStart);
                    eventEnd = new Date(sObj.getTime() + (2 * 60 * 60 * 1000)).toISOString();
                } catch (e) { }
            }
            if (eventEnd) {
                try {
                    if (new Date(eventEnd) < new Date()) {
                        computedGroupStatus = 'archived';
                    }
                } catch (e) { }
            }
        }

        return res.json({
            success: true,
            data: {
                id: doc.id,
                ...data,
                eventStartDate: eventStart,
                eventEndDate: eventEnd,
                computedStatus: computedGroupStatus,
                isLiked: !likeDoc.empty,
                createdAt: safeParseIso(data.createdAt),
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   DELETE /api/posts/:id
 * @desc    Delete a post (Author or Admin only) with Cascade Delete for Events
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

        // Cascade Deletion
        const batch = db.batch();
        batch.delete(postRef);

        if (data.isEvent) {
            // 1. Delete associated event_groups
            const groupSnap = await db.collection('event_groups').where('eventId', '==', req.params.id).get();
            groupSnap.docs.forEach(d => batch.delete(d.ref));

            // 2. Delete event_group_members
            const memberSnap = await db.collection('event_group_members').where('eventId', '==', req.params.id).get();
            memberSnap.docs.forEach(d => batch.delete(d.ref));

            // 3. Delete event_attendance
            const attendanceSnap = await db.collection('event_attendance').where('eventId', '==', req.params.id).get();
            attendanceSnap.docs.forEach(d => batch.delete(d.ref));

            logger.info({ postId: req.params.id }, 'Cascaded delete rules applied for Event');
        }

        await batch.commit();

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
 * @route   POST /api/posts/:id/messages
 * @desc    Send a chat message for an event/post
 */
router.post('/:id/messages', authenticate, async (req, res, next) => {
    try {
        const cleanBody = cleanPayload(req.body, ['text']);
        const { text } = cleanBody;
        if (!text) return res.status(400).json({ error: 'Message text is required' });
        const senderName = buildDisplayName({
            displayName: req.user.displayName,
            email: req.user.email,
            fallback: 'User'
        });

        const messageData = {
            senderId: req.user.uid,
            senderName,
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
