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
    mediaType: Joi.string().valid('image', 'video', 'text', 'none').default('none'),
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


        // 3. Shadow Ban Implementation
        // bad actors can still post, but their posts aren't visible to others
        const isShadowBanned = req.user.status === 'shadow_banned';
        const actorDisplayName = req.user.displayName || 'User';

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
            viewCount: 0,
            visibility: isShadowBanned ? 'shadow' : 'public',
            status: 'active',
            geoHash: geoHash,
            // Prefix search optimization
            title_lowercase: (value.title || '').toLowerCase(),
            body_lowercase: (value.body || value.text || '').toLowerCase()
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

        // Trigger mentions notifications
        const textToProcess = `${value.title || ''} ${value.body || ''} ${value.text || ''}`;
        _processMentions(textToProcess, uid).then(mentionUids => {
            mentionUids.forEach(targetUid => {
                _sendNotificationInternal({
                    toUserId: targetUid,
                    fromUserId: uid,
                    fromUserName: actorDisplayName,
                    fromUserProfileImage: req.user.photoURL,
                    type: 'mention',
                    postId: postRef.id,
                }).catch(err => logger.error('Post Mention Notification Error', { err: err.message }));
            });
        });

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
const USER_CONTEXT_CACHE = new Map();
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
 * Helper to get user's context (likes and muted users) via cache or DB
 *
 * Tradeoff note: Using a 30-second TTL cache for like state and muted users.
 * If a user likes a post and refreshes within 30 seconds, their like state 
 * might appear stale (unliked) strictly from the API response.
 * This is an acceptable tradeoff for "eventual consistency" in a high-read feed environment.
 * The Flutter client currently handles immediate UI updates via optimistic updates 
 * in 'feed_controller.dart' which masks this 30s delay perfectly.
 */
async function getUserContext(userId, postIds) {
    const contextKey = `user_context:${userId}`;
    let cachedContext = USER_CONTEXT_CACHE.get(contextKey);

    // Fallback context
    let likedPostIds = new Set();
    let mutedUserIds = new Set();

    if (cachedContext && (Date.now() - cachedContext.timestamp < CACHE_TTL)) {
        likedPostIds = cachedContext.data.likedIds;
        mutedUserIds = cachedContext.data.mutedIds;
    } else {
        // Fetch User Muted Users
        const userPromise = db.collection('users').doc(userId).get()
            .then(doc => doc.exists ? new Set(doc.data().mutedUsers || []) : new Set());

        // Optimize: Fetch up to 500 recent user likes.
        // This covers almost any realistic scrolling session and avoids N+1 chunk queries.
        const likesPromise = db.collection('likes')
            .where('userId', '==', userId)
            .orderBy('createdAt', 'desc')
            .limit(500)
            .get()
            .then(snap => new Set(snap.docs.map(doc => doc.data().postId)))
            .catch(err => {
                logger.warn({ userId }, 'Likes fetch error during context creation', err);
                return new Set();
            });

        const [mutedRes, likesRes] = await Promise.all([userPromise, likesPromise]);
        mutedUserIds = mutedRes;
        likedPostIds = likesRes;

        USER_CONTEXT_CACHE.set(contextKey, {
            timestamp: Date.now(),
            data: { likedIds: likedPostIds, mutedIds: mutedUserIds }
        });
    }

    return { likedPostIds, mutedUserIds };
}

/**
 * Helper to execute multiple geo-ring queries in parallel
 */
async function fetchGeoRingsParallel(lat, lng, pageSize) {
    const p6 = ngeohash.encode(parseFloat(lat), parseFloat(lng), 6);
    const p5 = ngeohash.encode(parseFloat(lat), parseFloat(lng), 5);
    const p4 = ngeohash.encode(parseFloat(lat), parseFloat(lng), 4);

    const rings = [
        { prefix: p6, label: 'hyper-local (~1km)' },
        { prefix: p5, label: 'local (~5km)' },
        { prefix: p4, label: 'regional (~40km)' }
    ];

    const ringPromises = rings.map(ring => {
        return db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('geoHash', '>=', ring.prefix)
            .where('geoHash', '<=', ring.prefix + '\uf8ff')
            .orderBy('geoHash')
            .orderBy('createdAt', 'desc')
            .limit(pageSize)
            .get()
            .then(snapshot => snapshot.docs.map(mapDocToPost))
            .catch(err => {
                logger.error({ error: err.message, ring: ring.label }, 'Ring fetch failed');
                return [];
            });
    });

    // Also fetch global fallback just in case rings are empty
    const globalPromise = db.collection('posts')
        .where('visibility', '==', 'public')
        .where('status', '==', 'active')
        .orderBy('createdAt', 'desc')
        .limit(pageSize)
        .get()
        .then(snapshot => snapshot.docs.map(mapDocToPost))
        .catch(err => {
            logger.error({ error: err.message }, 'Global fallback failed');
            return [];
        });

    const resultsArray = await Promise.all([...ringPromises, globalPromise]);

    // Flatten and deduplicate
    const results = [];
    const seenIds = new Set();

    for (const batch of resultsArray) {
        for (const post of batch) {
            if (!seenIds.has(post.id) && results.length < pageSize) {
                seenIds.add(post.id);
                results.push(post);
            }
        }
    }

    // Sort by distance
    const sortedResults = results.map(post => {
        const distance = getDistance(
            parseFloat(lat),
            parseFloat(lng),
            post.latitude || post.location?.lat,
            post.longitude || post.location?.lng
        );
        return { ...post, distance };
    }).sort((a, b) => a.distance - b.distance);

    return {
        success: true,
        data: sortedResults,
        pagination: {
            cursor: sortedResults.length > 0 ? sortedResults[sortedResults.length - 1].id : null,
            hasMore: sortedResults.length === pageSize
        }
    };
}


/**
 * @route   GET /api/posts
 * @desc    Get paginated feed with parallelized fetches
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        console.time('[FEED] Total Request Time');
        console.time('[FEED] 1. Resolve Posts & Cache');
        const { authorId, category, city, lat, lng, country, feedType, limit = 20, afterId } = req.query;
        const isLocalFeed = feedType === 'local';
        logger.info({
            query: { lat, lng, category, city, country, afterId },
            user: { uid: req.user.uid, country: req.user.country }
        }, '[FEED_DEBUG] Fetching posts');
        const pageSize = Math.min(parseInt(limit), 50);
        const { uid } = req.user;

        // REMOVED: Artificial Jitter delay
        const jitterPromise = Promise.resolve();

        // ∩┐╜∩┐╜∩┐╜ 1. GeoHash & Cache Check ∩┐╜∩┐╜∩┐╜
        let geoHash = null;
        if (lat && lng) {
            geoHash = ngeohash.encode(parseFloat(lat), parseFloat(lng), 5);
        }

        const cacheKey = geoHash
            ? `feed:${geoHash}:${pageSize}:${afterId || 'page1'}`
            : `feed:global:${pageSize}:${afterId || 'page1'}`;

        let responseDataPromise;

        const cached = FEED_CACHE.get(cacheKey);
        if (cached && (Date.now() - cached.timestamp < CACHE_TTL) && !authorId && !category && !city) {
            logger.debug({ geoHash, cacheKey }, 'Serving regional feed from in-memory cache');
            responseDataPromise = Promise.resolve(cached.data);
        } else if (FETCH_LOCKS.has(cacheKey) && !authorId && !category && !city) {
            logger.debug({ cacheKey }, 'Awaiting existing fetch lock for region');
            responseDataPromise = FETCH_LOCKS.get(cacheKey);
        } else {
            // ∩┐╜∩┐╜∩┐╜ 2. Query Construction & Execution ∩┐╜∩┐╜∩┐╜
            responseDataPromise = (async () => {
                // Multi-Ring Fetch in Parallel
                if (isLocalFeed && lat && lng && !authorId && !category && !city && !afterId) {
                    logger.debug({ lat, lng }, 'Executing Parallel Multi-Ring expansion');
                    return await fetchGeoRingsParallel(lat, lng, pageSize);
                }

                // Default Single-Query Logic (Global Feed or Paginated)
                let query = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active');

                if (authorId) query = query.where('authorId', '==', authorId);
                if (category) query = query.where('category', '==', category);
                if (city) query = query.where('city', '==', city);

                if (isLocalFeed && geoHash && !authorId && !category && !city) {
                    query = query.where('geoHash', '>=', geoHash)
                        .where('geoHash', '<=', geoHash + '\uf8ff');
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

                let posts = snapshot.docs.map(mapDocToPost);

                // Sort appropriately
                if (isLocalFeed && lat && lng) {
                    posts = posts.map(post => {
                        const distance = getDistance(
                            parseFloat(lat),
                            parseFloat(lng),
                            post.latitude || post.location?.lat,
                            post.longitude || post.location?.lng
                        );
                        return { ...post, distance };
                    }).sort((a, b) => a.distance - b.distance);
                } else if (!isLocalFeed) {
                    posts = posts.map(post => {
                        const trendingScore = (post.likeCount || 0) + (post.commentCount || 0) * 2;
                        return { ...post, trendingScore };
                    }).sort((a, b) => b.trendingScore - a.trendingScore);
                }

                return {
                    success: true,
                    data: posts,
                    pagination: {
                        cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
                        hasMore: posts.length === pageSize
                    }
                };
            })();

            // Lock and Cache Management
            if (!authorId && !category && !city) {
                FETCH_LOCKS.set(cacheKey, responseDataPromise);
                responseDataPromise.then(data => {
                    FEED_CACHE.set(cacheKey, { timestamp: Date.now(), data });
                    FETCH_LOCKS.delete(cacheKey);
                }).catch(() => FETCH_LOCKS.delete(cacheKey));
            }
        }

        // Wait for Feed Data
        const responseData = await responseDataPromise;
        const postIds = (responseData.data || []).map(p => p.id);
        console.timeEnd('[FEED] 1. Resolve Posts & Cache');

        console.time('[FEED] 2. User Context & Jitter');

        // ∩┐╜∩┐╜∩┐╜ 3. Fetch User Context (Likes & Muted Users) Parallel to Jitter ∩┐╜∩┐╜∩┐╜
        const userContextPromise = getUserContext(uid, postIds);

        // Wait for Context and Jitter
        const [userContext] = await Promise.all([userContextPromise, jitterPromise]);
        console.timeEnd('[FEED] 2. User Context & Jitter');

        // 4. Apply Context (Filter & Embed Liked State)
        let finalPosts = responseData.data || [];

        if (userContext.mutedUserIds.size > 0) {
            finalPosts = finalPosts.filter(post => !userContext.mutedUserIds.has(post.authorId));
        }

        finalPosts = finalPosts.map(post => ({
            ...post,
            isLiked: userContext.likedPostIds.has(post.id)
        }));

        // CRITICAL FIX: Ensure strict distance sorting for Local Feed
        if (isLocalFeed && lat && lng) {
            finalPosts.sort((a, b) => (a.distance || 9999) - (b.distance || 9999));
        }

        console.timeEnd('[FEED] 3. Data Processing');
        console.timeEnd('[FEED] Total Request Time');

        return res.json({
            ...responseData,
            data: finalPosts
        });

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

/**
 * @route   POST /api/posts/:id/view
 * @desc    Track a post view
 */
router.post('/:id/view', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const userId = req.user.uid;

        // Get user location data
        const userDoc = await db.collection('users').doc(userId).get();
        const userData = userDoc.data();

        const viewData = {
            userId,
            userName: buildDisplayName({
                displayName: req.user.displayName,
                username: userData?.username,
                firstName: userData?.firstName,
                lastName: userData?.lastName,
                email: userData?.email || req.user.email,
                fallback: 'User'
            }),
            userAvatar: req.user.photoURL,
            location: userData?.city || null,
            viewedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        // Store the view in a subcollection
        const viewRef = db.collection('posts').doc(postId).collection('views').doc(userId);
        await viewRef.set(viewData, { merge: true });

        // Increment view count on the post
        await db.collection('posts').doc(postId).update({
            viewCount: admin.firestore.FieldValue.increment(1)
        });

        return res.json({
            success: true,
            data: { viewed: true },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   GET /api/posts/:id/insights
 * @desc    Get post insights (views, viewer info)
 */
router.get('/:id/insights', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const userId = req.user.uid;

        // Check if user owns the post
        const postDoc = await db.collection('posts').doc(postId).get();
        if (!postDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'Post not found'
            });
        }

        const postData = postDoc.data();
        if (postData.authorId !== userId) {
            return res.status(403).json({
                success: false,
                error: 'You can only view insights for your own posts'
            });
        }

        // Get view count
        const viewCount = postData.viewCount || 0;

        // Get viewers from subcollection
        const viewsSnapshot = await db.collection('posts')
            .doc(postId)
            .collection('views')
            .orderBy('viewedAt', 'desc')
            .limit(100)
            .get();

        const viewers = viewsSnapshot.docs.map(doc => ({
            ...doc.data(),
            viewedAt: doc.data().viewedAt?.toDate()?.toISOString()
        }));

        return res.json({
            success: true,
            data: {
                viewCount,
                viewers
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

/**
 * @route   POST /api/posts/:id/report
 * @desc    Report a post for violation
 */
router.post('/:id/report', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const reporterId = req.user.uid;
        const { reason } = req.body;

        // Validate reason
        const validReasons = [
            'Spam or misleading',
            'Harassment or hate speech',
            'Violence or dangerous content',
            'Nudity or sexual content',
            'False information',
            'Intellectual property violation',
            'Something else'
        ];

        if (!reason || !validReasons.includes(reason)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid or missing report reason'
            });
        }

        // Check if post exists
        const postDoc = await db.collection('posts').doc(postId).get();
        if (!postDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'Post not found'
            });
        }

        const postData = postDoc.data();

        // Prevent reporting own posts
        if (postData.authorId === reporterId) {
            return res.status(400).json({
                success: false,
                error: 'You cannot report your own post'
            });
        }

        // Store report
        const reportData = {
            postId,
            postAuthorId: postData.authorId,
            reporterId,
            reporterName: buildDisplayName({
                displayName: req.user.displayName,
                email: req.user.email,
                fallback: 'User'
            }),
            reason,
            status: 'pending', // pending, reviewed, dismissed, action_taken
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            postTitle: postData.title || postData.body?.substring(0, 100) || 'Untitled',
            postMediaUrl: postData.mediaUrl || null
        };

        const reportRef = await db.collection('reports').add(reportData);

        // Increment report count on post (for auto-flagging)
        await db.collection('posts').doc(postId).update({
            reportCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // Auto-flag if multiple reports (threshold: 5)
        const updatedPostDoc = await db.collection('posts').doc(postId).get();
        const reportCount = updatedPostDoc.data().reportCount || 0;

        if (reportCount >= 5) {
            await db.collection('posts').doc(postId).update({
                visibility: 'flagged', // Flagged for review
                flaggedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            logger.warn({ postId, reportCount }, 'Post auto-flagged due to multiple reports');
        }

        // Log audit trail
        await AuditService.logAction({
            userId: reporterId,
            action: 'POST_REPORTED',
            metadata: { postId, reason, reportId: reportRef.id },
            req
        });

        logger.info({ postId, reporterId, reason }, 'Post reported successfully');

        return res.json({
            success: true,
            data: {
                reported: true,
                reportId: reportRef.id,
                postId
            },
            error: null
        });
    } catch (err) {
        next(err);
    }
});

// ============================================
// HELPER FUNCTIONS (used by post creation for mentions)
// ============================================

/**
 * Extracts @mentions from text and returns unique list of mentioned uids
 */
async function _processMentions(text, currentUserId) {
    if (!text) return [];
    const mentionRegex = /@([a-zA-Z0-9._]+)/g;
    const matches = [...text.matchAll(mentionRegex)];
    if (matches.length === 0) return [];

    const usernames = [...new Set(matches.map(m => m[1].toLowerCase()))];
    const mentionUids = [];

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
 * Creates a notification document in Firestore
 */
async function _sendNotificationInternal({ toUserId, fromUserId, fromUserName, fromUserProfileImage, type, postId, postThumbnail, commentText }) {
    if (!toUserId || toUserId === fromUserId) return;
    try {
        const notificationData = {
            toUserId,
            fromUserId,
            fromUserName: fromUserName || 'Someone',
            fromUserProfileImage: fromUserProfileImage || null,
            type,
            isRead: false,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

        if (postId !== undefined) notificationData.postId = postId;
        if (postThumbnail !== undefined) notificationData.postThumbnail = postThumbnail;
        if (commentText !== undefined) notificationData.commentText = commentText;

        await db.collection('notifications').add(notificationData);
    } catch (err) {
        logger.error('Notification creation failed', { err: err.message, toUserId, type });
    }
}

export default router;
