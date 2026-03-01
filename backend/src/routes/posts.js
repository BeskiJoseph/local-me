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
import { geoIndex } from '../services/geoIndex.js';

const router = express.Router();

// ============================================================
//  HAVERSINE DISTANCE FORMULA (km)
// ============================================================
function getDistance(lat1, lon1, lat2, lon2) {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) return 999999;
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ============================================================
//  GEOHASH PRECISION SELECTOR
//  Returns precision based on how far we've already scrolled
// ============================================================
function getPrecisionForDistance(distanceKm) {
    if (distanceKm < 0.1) return 7; // 150m cell -> ~450m radius search. OK.
    if (distanceKm < 0.5) return 6; // 1.2km cell -> ~3.6km radius. OK.
    if (distanceKm < 2) return 5; // 4.9km cell -> ~15km radius. OK.
    if (distanceKm < 20) return 4; // 39km cell  -> ~117km radius. OK.
    if (distanceKm < 100) return 3; // 156km cell -> ~468km radius. OK.
    if (distanceKm < 500) return 2; // 1250km cell -> ~3750km radius. OK.
    return 1; // 5000km cell -> Whole world.
}

// ============================================================
//  POST SCHEMA VALIDATION
// ============================================================
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
    eventDate: Joi.date().iso().allow(null).optional(),
    eventLocation: Joi.string().max(200).allow(null).optional(),
    isFree: Joi.boolean().default(true),
    eventType: Joi.string().max(50).allow(null).optional(),
    subtitle: Joi.string().max(500).allow(null, '').optional()
}).or('text', 'mediaUrl', 'title').unknown(true);

// ============================================================
//  IN-MEMORY CACHE (Global feed only — NOT used for local feed)
// ============================================================
export const FEED_CACHE = new Map();
export const USER_CONTEXT_CACHE = new Map();
const FETCH_LOCKS = new Map();
const CACHE_TTL = 15 * 1000;        // 15s for local/author/category queries
const GLOBAL_CACHE_TTL = 5 * 60 * 1000;  // 5 minutes for global trending feed

// ============================================================
//  TIME-DECAY TRENDING SCORE
//
//  Hybrid Strategy:
//    - High weights for active engagement (likes/comments)
//    - Logarithmic boost for passive engagement (views)
//    - Momentum baseline (+1) ensures brand-new posts don't tie at 0
//    - Gravity 1.4 allows quality content to stay trending for ~24-48h
// ============================================================
function computeTrendingScore(post, gravity = 1.4) {
    const likes = post.likeCount || 0;
    const comments = post.commentCount || 0;
    const views = post.viewCount || 0;

    // Weighting: Comment (10) > Like (5) > View (0.5)
    // +1 momentum ensures a non-zero score for brand-new posts
    const engagement = (likes * 5) + (comments * 10) + (views * 0.5) + 1;

    // Age in hours
    let ageHours = 0;
    if (post.createdAt) {
        const createdMs = new Date(post.createdAt).getTime();
        ageHours = (Date.now() - createdMs) / 3600000;
    }

    // Clamp age to 0.5h so brand-new posts don't have infinite scores
    const age = Math.max(ageHours, 0.5);

    return engagement / Math.pow(age + 2, gravity);
}

// ============================================================
//  INTERACTION DELTAS — Instagram-Level Consistency Layer
//  Stores recent interactions before Firestore index syncs (up to 60s)
// ============================================================
const INTERACTION_DELTAS = {
    likes: new Map(),
    unlikes: new Map(),
    counts: new Map(),
    follows: new Map(),
    unfollows: new Map()
};

const trackDelta = (map, key, value, add = true) => {
    if (!map.has(key)) map.set(key, new Set());
    const set = map.get(key);
    if (add) set.add(value); else set.delete(value);
    setTimeout(() => { if (set.has(value)) set.delete(value); }, 60000);
};

const trackCountDelta = (postId, delta) => {
    const current = INTERACTION_DELTAS.counts.get(postId) || 0;
    INTERACTION_DELTAS.counts.set(postId, current + delta);
    setTimeout(() => {
        const val = INTERACTION_DELTAS.counts.get(postId) || 0;
        INTERACTION_DELTAS.counts.set(postId, val - delta);
    }, 60000);
};

export const updateUserContextCache = (userId, targetId, action = 'invalidate') => {
    const key = `user_context:${userId}`;

    switch (action) {
        case 'like':
            trackDelta(INTERACTION_DELTAS.likes, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.unlikes, userId, targetId, false);
            trackCountDelta(targetId, 1);
            break;
        case 'unlike':
            trackDelta(INTERACTION_DELTAS.unlikes, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.likes, userId, targetId, false);
            trackCountDelta(targetId, -1);
            break;
        case 'follow':
            trackDelta(INTERACTION_DELTAS.follows, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.unfollows, userId, targetId, false);
            break;
        case 'unfollow':
            trackDelta(INTERACTION_DELTAS.unfollows, userId, targetId, true);
            trackDelta(INTERACTION_DELTAS.follows, userId, targetId, false);
            break;
    }

    if (!USER_CONTEXT_CACHE.has(key)) return;
    const cached = USER_CONTEXT_CACHE.get(key);
    if (!cached?.data) return;

    const { likedIds, mutedIds, followedIds } = cached.data;
    switch (action) {
        case 'like': likedIds.add(targetId); break;
        case 'unlike': likedIds.delete(targetId); break;
        case 'mute': mutedIds.add(targetId); break;
        case 'unmute': mutedIds.delete(targetId); break;
        case 'follow': if (followedIds) followedIds.add(targetId); break;
        case 'unfollow': if (followedIds) followedIds.delete(targetId); break;
    }
    USER_CONTEXT_CACHE.set(key, cached);
};

export const invalidateUserContext = (userId) => updateUserContextCache(userId, null, 'invalidate');
export const invalidateFeedCache = () => { FEED_CACHE.clear(); };

// ============================================================
//  SAFE DATE PARSER
// ============================================================
const safeParseIso = (val) => {
    if (!val) return null;
    try {
        if (typeof val.toDate === 'function') return val.toDate().toISOString();
        const d = new Date(val);
        return isNaN(d.getTime()) ? null : d.toISOString();
    } catch { return null; }
};

// ============================================================
//  MAP FIRESTORE DOC → POST OBJECT
// ============================================================
const mapDocToPost = (doc) => {
    const d = doc.data();
    const isEvent = !!(d.isEvent || (d.category && d.category.toLowerCase() === 'events'));

    let eventStart = safeParseIso(d.eventStartDate);
    let eventEnd = safeParseIso(d.eventEndDate);
    let computedGroupStatus = 'active';

    if (isEvent) {
        const fallback = safeParseIso(d.eventDate);
        if (!eventStart && fallback) eventStart = fallback;
        if (!eventEnd && eventStart) {
            try { eventEnd = new Date(new Date(eventStart).getTime() + 2 * 3600000).toISOString(); } catch { }
        }
        if (eventEnd) {
            try { if (new Date(eventEnd) < new Date()) computedGroupStatus = 'archived'; } catch { }
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
        viewCount: d.viewCount || 0,
        isEvent,
        eventStartDate: eventStart,
        eventEndDate: eventEnd,
        computedStatus: computedGroupStatus,
        createdAt: safeParseIso(d.createdAt),
        city: d.city,
        country: d.country,
        category: d.category || 'General',
        latitude: d.location?.lat ?? d.latitude,
        longitude: d.location?.lng ?? d.longitude,
        attendeeCount: d.attendeeCount || 0,
        geoHash: d.geoHash
    };
};

// ============================================================
//  USER CONTEXT (Likes, Muted, Followed)
// ============================================================
export async function getUserContext(userId) {
    const contextKey = `user_context:${userId}`;
    const cachedContext = USER_CONTEXT_CACHE.get(contextKey);

    let likedPostIds = new Set();
    let mutedUserIds = new Set();
    let followedUserIds = new Set();

    if (cachedContext && (Date.now() - cachedContext.timestamp < CACHE_TTL)) {
        likedPostIds = cachedContext.data.likedIds;
        mutedUserIds = cachedContext.data.mutedIds;
        followedUserIds = cachedContext.data.followedIds || new Set();
    } else {
        const [mutedRes, likesRes, followsRes] = await Promise.all([
            db.collection('users').doc(userId).get()
                .then(doc => new Set(doc.exists ? doc.data().mutedUsers || [] : []))
                .catch(() => new Set()),
            db.collection('likes').where('userId', '==', userId)
                .orderBy('createdAt', 'desc').limit(500).get()
                .then(snap => new Set(snap.docs.map(d => d.data().postId)))
                .catch(() => new Set()),
            db.collection('follows').where('followerId', '==', userId)
                .limit(1000).get()
                .then(snap => new Set(snap.docs.map(d => d.data().followingId)))
                .catch(() => new Set())
        ]);

        likedPostIds = likesRes;
        mutedUserIds = mutedRes;
        followedUserIds = followsRes;

        USER_CONTEXT_CACHE.set(contextKey, {
            timestamp: Date.now(),
            data: { likedIds: likedPostIds, mutedIds: mutedUserIds, followedIds: followedUserIds }
        });
    }

    // Patch with in-flight deltas
    const pendingLikes = INTERACTION_DELTAS.likes.get(userId);
    const pendingUnlikes = INTERACTION_DELTAS.unlikes.get(userId);
    const pendingFollows = INTERACTION_DELTAS.follows.get(userId);
    const pendingUnfollows = INTERACTION_DELTAS.unfollows.get(userId);

    if (pendingLikes) pendingLikes.forEach(id => likedPostIds.add(id));
    if (pendingUnlikes) pendingUnlikes.forEach(id => likedPostIds.delete(id));
    if (pendingFollows) pendingFollows.forEach(id => followedUserIds.add(id));
    if (pendingUnfollows) pendingUnfollows.forEach(id => followedUserIds.delete(id));

    return { likedPostIds, mutedUserIds, followedUserIds };
}

//  ⭐ CORE: IN-MEMORY DISTANCE FEED
//  Queries the RAM index first, then fetches docs from Firestore
// ============================================================
async function fetchLocalFeedWithCursor(
    lat, lng,
    lastDistance, lastPostId,
    watchedIdsSet, pageSize
) {
    const startTime = Date.now();

    // STEP 1: Check if geoIndex is ready
    if (!geoIndex || !geoIndex.isReady) {
        logger.info('[FEED] GeoIndex not ready yet. Using Firestore fallback.');
        return fetchFromFirestoreFallback(lat, lng, lastDistance, lastPostId, watchedIdsSet, pageSize);
    }

    // STEP 2: Query in-memory index
    const geoStartTime = Date.now();
    const geoResults = geoIndex.query({
        userLat: parseFloat(lat),
        userLng: parseFloat(lng),
        lastDistance,
        lastPostId,
        watchedIdsSet,
        limit: pageSize * 3
    });
    const geoQueryMs = Date.now() - geoStartTime;

    // STEP 3: If 0 results returned
    if (geoResults.length === 0) {
        return {
            success: true,
            data: [],
            pagination: {
                lastDistance,
                lastPostId,
                hasMore: false,
                cursor: null,
                fallbackLevel: 'distance'
            }
        };
    }

    // STEP 4: Fetch full post data from Firestore in parallel
    const firestoreStartTime = Date.now();
    const pageResults = geoResults.slice(0, pageSize);

    const postDocs = await Promise.all(
        pageResults.map(({ postId }) =>
            db.collection('posts').doc(postId).get()
        )
    );
    const firestoreMs = Date.now() - firestoreStartTime;

    // STEP 5: Build final post objects
    const finalPosts = [];
    postDocs.forEach((doc, index) => {
        if (doc.exists) {
            const data = doc.data();
            if (data.status === 'active' && data.visibility === 'public') {
                const post = mapDocToPost(doc);
                post.distance = pageResults[index].distance;
                finalPosts.push(post);
            }
        }
    });

    finalPosts.sort((a, b) => a.distance - b.distance);

    const lastPost = finalPosts[finalPosts.length - 1];
    const totalMs = Date.now() - startTime;

    logger.info({
        geoQueryMs,
        firestoreMs,
        totalMs,
        indexSize: geoIndex.size,
        returned: finalPosts.length,
        nearest: finalPosts[0]?.distance?.toFixed(2),
        farthest: lastPost?.distance?.toFixed(2)
    }, '[LOCAL FEED] Memory query complete');

    return {
        success: true,
        data: finalPosts,
        pagination: {
            lastDistance: lastPost ? parseFloat(lastPost.distance.toFixed(6)) : lastDistance,
            lastPostId: lastPost ? lastPost.id : lastPostId,
            hasMore: geoResults.length > pageSize,
            cursor: lastPost ? lastPost.id : null,
            fallbackLevel: 'distance'
        }
    };
}

async function fetchFromFirestoreFallback(
    lat, lng, lastDistance, lastPostId, watchedIdsSet, pageSize
) {
    const userLat = parseFloat(lat);
    const userLng = parseFloat(lng);
    const centerHash = ngeohash.encode(userLat, userLng, 5);
    const prefixes = [centerHash, ...ngeohash.neighbors(centerHash)];

    const ringBatches = await Promise.all(
        prefixes.map(prefix =>
            db.collection('posts')
                .where('visibility', '==', 'public')
                .where('status', '==', 'active')
                .where('geoHash', '>=', prefix)
                .where('geoHash', '<=', prefix + '\uf8ff')
                .orderBy('geoHash')
                .orderBy('createdAt', 'desc')
                .limit(200)
                .get()
                .then(snap => snap.docs.map(mapDocToPost))
                .catch(() => [])
        )
    );

    let pool = [];
    const seenIds = new Set();
    ringBatches.forEach(batch => batch.forEach(p => {
        if (!seenIds.has(p.id)) {
            seenIds.add(p.id);
            pool.push(p);
        }
    }));

    const results = pool.map(p => ({
        ...p,
        distance: getDistance(userLat, userLng, p.latitude, p.longitude)
    })).filter(p => {
        if (watchedIdsSet.has(p.id)) return false;
        if (p.distance < lastDistance - 0.001) return false;
        if (lastPostId && Math.abs(p.distance - lastDistance) < 0.001 && p.id <= lastPostId) return false;
        return true;
    });

    results.sort((a, b) => {
        if (Math.abs(a.distance - b.distance) < 0.001) return a.id.localeCompare(b.id);
        return a.distance - b.distance;
    });

    const page = results.slice(0, pageSize);
    const lastPost = page[page.length - 1];

    return {
        success: true,
        data: page,
        pagination: {
            lastDistance: lastPost ? parseFloat(lastPost.distance.toFixed(6)) : lastDistance,
            lastPostId: lastPost ? lastPost.id : lastPostId,
            hasMore: results.length > pageSize,
            cursor: lastPost ? lastPost.id : null,
            fallbackLevel: 'fallback'
        }
    };
}

/**
 * GET /api/posts/new-since
 * Poll for new posts created after a certain timestamp
 */
router.get('/new-since', authenticate, async (req, res, next) => {
    try {
        const { lat, lng, sinceTimestamp, maxDistance } = req.query;
        if (!lat || !lng || !sinceTimestamp) {
            return res.status(400).json({ success: false, error: 'Missing required params' });
        }

        const since = new Date(parseInt(sinceTimestamp));
        const userLat = parseFloat(lat);
        const userLng = parseFloat(lng);

        const snapshot = await db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(since))
            .orderBy('createdAt', 'desc')
            .limit(50)
            .get();

        let newPosts = snapshot.docs.map(mapDocToPost).map(post => ({
            ...post,
            distance: getDistance(userLat, userLng, post.latitude, post.longitude)
        }));

        // Only return posts nearer than user's current scroll position if maxDistance is provided
        if (maxDistance) {
            const maxD = parseFloat(maxDistance);
            newPosts = newPosts.filter(p => p.distance <= maxD);
        }

        // Sort by distance ASC
        newPosts.sort((a, b) => a.distance - b.distance);

        return res.json({
            success: true,
            data: newPosts,
            count: newPosts.length
        });
    } catch (error) {
        next(error);
    }
});

// ============================================================
//  POST /api/posts — Create Post
// ============================================================
router.post('/', authenticate, async (req, res, next) => {
    logger.debug({ body: Object.keys(req.body) }, 'Incoming POST /api/posts');
    try {
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
                const err = new Error('eventStartDate and eventEndDate are required');
                err.status = 400; return next(err);
            }
            if (new Date(value.eventEndDate) <= new Date(value.eventStartDate)) {
                const err = new Error('eventEndDate must be after eventStartDate');
                err.status = 400; return next(err);
            }
        }

        const { uid } = req.user;
        const isShadowBanned = req.user.status === 'shadow_banned';
        const actorDisplayName = req.user.displayName || 'User';

        let geoHash = null;
        if (value.location?.lat && value.location?.lng) {
            geoHash = ngeohash.encode(value.location.lat, value.location.lng, 5);
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
            geoHash,
            title_lowercase: (value.title || '').toLowerCase(),
            body_lowercase: (value.body || value.text || '').toLowerCase()
        };

        const postRef = db.collection('posts').doc(value.id || db.collection('posts').doc().id);

        await db.runTransaction(async (transaction) => {
            transaction.set(postRef, postData);
            if (value.isEvent) {
                const groupRef = db.collection('event_groups').doc();
                transaction.set(groupRef, {
                    eventId: postRef.id,
                    creatorId: uid,
                    groupStatus: 'active',
                    createdAt: admin.firestore.FieldValue.serverTimestamp()
                });
                const memberRef = db.collection('event_group_members').doc(`${postRef.id}_${uid}`);
                transaction.set(memberRef, {
                    eventId: postRef.id,
                    userId: uid,
                    role: 'admin',
                    joinedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        });

        // Add to RAM index
        geoIndex.add(postRef.id, value.location?.lat, value.location?.lng);

        FEED_CACHE.clear();

        await AuditService.logAction({
            userId: uid, action: 'POST_CREATED',
            metadata: { postId: postRef.id, isShadow: isShadowBanned }, req
        });

        const textToProcess = `${value.title || ''} ${value.body || ''} ${value.text || ''}`;
        _processMentions(textToProcess, uid).then(mentionUids => {
            mentionUids.forEach(targetUid => {
                _sendNotificationInternal({
                    toUserId: targetUid, fromUserId: uid,
                    fromUserName: actorDisplayName,
                    fromUserProfileImage: req.user.photoURL,
                    type: 'mention', postId: postRef.id,
                }).catch(err => logger.error('Mention notification error', { err: err.message }));
            });
        });

        return res.status(201).json({
            success: true,
            data: { id: postRef.id, ...postData, createdAt: new Date().toISOString() },
            error: null
        });
    } catch (err) { next(err); }
});

// ============================================================
//  GET /api/posts — Paginated Feed
//
//  Local feed query params:
//    feedType=local
//    lat, lng          — user GPS coordinates (required for local)
//    lastDistance      — distance cursor (km) from previous page
//    lastPostId        — postId tiebreaker cursor from previous page
//    watchedIds        — comma-separated list of already-seen post IDs
//    limit             — page size (default 20, max 50)
//
//  Global feed query params:
//    feedType=global
//    afterId           — Firestore cursor (last post ID of previous page)
//    limit             — page size
// ============================================================
router.get('/', authenticate, async (req, res, next) => {
    try {
        const {
            authorId, category, city, lat, lng, country,
            feedType, limit = 20, afterId,
            lastDistance, lastPostId, watchedIds
        } = req.query;

        const isLocalFeed = feedType === 'local';
        const pageSize = Math.min(parseInt(limit), 50);
        const { uid } = req.user;

        logger.info({ feedType, lat, lng, lastDistance, lastPostId, uid }, '[FEED] Request');

        // ── LOCAL FEED: Use strict distance cursor engine ──
        // Only trigger distance engine if lat/lng present and it's not a specific author query
        if (isLocalFeed && lat && lng && !authorId && !category) {

            const distanceCursor = parseFloat(lastDistance) || 0;
            const postIdCursor = lastPostId || null;
            const watchedSet = watchedIds
                ? new Set(watchedIds.split(',').filter(Boolean))
                : new Set();

            const responseData = await fetchLocalFeedWithCursor(
                lat, lng,
                distanceCursor,
                postIdCursor,
                watchedSet,
                pageSize
            );

            // Apply user context (likes, muted users)
            const userContext = await getUserContext(uid);

            let finalPosts = (responseData.data || []).filter(
                post => !userContext.mutedUserIds.has(post.authorId)
            );

            finalPosts = finalPosts.map(post => {
                const delta = INTERACTION_DELTAS.counts.get(post.id) || 0;
                return {
                    ...post,
                    isLiked: userContext.likedPostIds.has(post.id),
                    isFollowing: userContext.followedUserIds.has(post.authorId),
                    likeCount: (post.likeCount || 0) + delta
                };
            });

            return res.json({
                ...responseData,
                data: finalPosts
            });
        }

        // ── GLOBAL TRENDING FEED ──
        // Strategy:
        //   1. Fetch last 200 posts from past 72 hours (recent window only)
        //   2. Apply time-decay trending score in memory
        //   3. Sort by trendingScore DESC
        //   4. Paginate using offset (afterId → find index → slice)
        //   5. Cache full sorted list for 5 minutes (expensive to recompute)
        //
        // For author/category/city filtered queries → no trending, just recency

        const isFilteredQuery = !!(authorId || category || city || country);
        const cacheKey = isFilteredQuery
            ? `feed:filtered:${authorId || ''}:${category || ''}:${city || ''}:${pageSize}:${afterId || 'p1'}`
            : `feed:global:trending:${uid}:${pageSize}`;

        let responseDataPromise;
        const cached = FEED_CACHE.get(cacheKey);
        const activeCacheTTL = isFilteredQuery ? CACHE_TTL : GLOBAL_CACHE_TTL;

        if (cached && (Date.now() - cached.timestamp < activeCacheTTL)) {
            responseDataPromise = Promise.resolve(cached.data);
        } else if (FETCH_LOCKS.has(cacheKey)) {
            responseDataPromise = FETCH_LOCKS.get(cacheKey);
        } else {
            responseDataPromise = (async () => {

                // ── Filtered query (author / category / city) — simple recency ──
                if (isFilteredQuery) {
                    let query = db.collection('posts')
                        .where('visibility', '==', 'public')
                        .where('status', '==', 'active');

                    if (authorId) query = query.where('authorId', '==', authorId);
                    if (category) query = query.where('category', '==', category);
                    if (city) query = query.where('city', '==', city);

                    query = query.orderBy('createdAt', 'desc');

                    if (afterId) {
                        const lastDoc = await db.collection('posts').doc(afterId).get();
                        if (lastDoc.exists) query = query.startAfter(lastDoc);
                    }

                    let snapshot;
                    try {
                        snapshot = await query.limit(pageSize).get();
                    } catch (indexErr) {
                        if (indexErr.code === 9 || indexErr.message?.includes('index')) {
                            logger.error('Missing Firestore composite index', { query: req.query });
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
                            cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
                            hasMore: posts.length === pageSize
                        }
                    };
                }

                // ── Global trending feed — time-decay scoring ──
                // Fetch posts from the past 72 hours only (trending window)
                const windowStart = new Date(Date.now() - 72 * 3600000);

                let snapshot;
                try {
                    snapshot = await db.collection('posts')
                        .where('visibility', '==', 'public')
                        .where('status', '==', 'active')
                        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(windowStart))
                        .orderBy('createdAt', 'desc')
                        .limit(200) // Fetch pool — score + sort in memory
                        .get();
                } catch (indexErr) {
                    if (indexErr.code === 9 || indexErr.message?.includes('index')) {
                        logger.error('Missing Firestore index for trending feed');
                        // Fallback: fetch without date filter
                        snapshot = await db.collection('posts')
                            .where('visibility', '==', 'public')
                            .where('status', '==', 'active')
                            .orderBy('createdAt', 'desc')
                            .limit(200)
                            .get();
                    } else {
                        throw indexErr;
                    }
                }

                // Score every post with refined time-decay formula
                let posts = snapshot.docs.map(mapDocToPost).map(post => ({
                    ...post,
                    trendingScore: computeTrendingScore(post, 1.4)
                }));

                // Sort: Higher score first. 
                // Tiebreaker: Most likes first.
                posts.sort((a, b) => {
                    if (b.trendingScore !== a.trendingScore) {
                        return b.trendingScore - a.trendingScore;
                    }
                    return (b.likeCount || 0) - (a.likeCount || 0);
                });

                // Dedup against recently seen posts
                const watchedSet = watchedIds
                    ? new Set(watchedIds.split(',').filter(Boolean))
                    : new Set();
                posts = posts.filter(p => !watchedSet.has(p.id));

                logger.info({ count: posts.length, watchedCount: watchedSet.size }, '[FEED] Global trending pool scored, sorted, and filtered');

                return {
                    success: true,
                    _allPosts: posts, // Full sorted list stored in cache
                    data: posts.slice(0, pageSize),
                    pagination: {
                        cursor: posts.length > pageSize ? posts[pageSize - 1].id : null,
                        hasMore: posts.length > pageSize
                    }
                };
            })();

            FETCH_LOCKS.set(cacheKey, responseDataPromise);
            responseDataPromise.then(data => {
                FEED_CACHE.set(cacheKey, { timestamp: Date.now(), data });
                FETCH_LOCKS.delete(cacheKey);
            }).catch(() => FETCH_LOCKS.delete(cacheKey));
        }

        // ── Handle pagination for global trending (offset by afterId) ──
        let resolvedData = await responseDataPromise;

        if (!isFilteredQuery && afterId && resolvedData._allPosts) {
            const allPosts = resolvedData._allPosts;
            const afterIndex = allPosts.findIndex(p => p.id === afterId);
            const startIndex = afterIndex >= 0 ? afterIndex + 1 : 0;
            const pagePosts = allPosts.slice(startIndex, startIndex + pageSize);
            const nextPost = allPosts[startIndex + pageSize];

            resolvedData = {
                ...resolvedData,
                data: pagePosts,
                pagination: {
                    cursor: pagePosts.length > 0 ? pagePosts[pagePosts.length - 1].id : null,
                    hasMore: !!nextPost
                }
            };
        }

        const userContext = await getUserContext(uid);

        let finalPosts = (resolvedData.data || []).filter(
            post => !userContext.mutedUserIds.has(post.authorId)
        );

        finalPosts = finalPosts.map(post => {
            const delta = INTERACTION_DELTAS.counts.get(post.id) || 0;
            return {
                ...post,
                isLiked: userContext.likedPostIds.has(post.id),
                isFollowing: userContext.followedUserIds.has(post.authorId),
                likeCount: (post.likeCount || 0) + delta
            };
        });

        return res.json({
            success: resolvedData.success,
            data: finalPosts,
            pagination: resolvedData.pagination,
            error: null
        });

    } catch (err) { return next(err); }
});

// ============================================================
//  GET /api/posts/:id — Single Post
// ============================================================
router.get('/:id', authenticate, async (req, res, next) => {
    try {
        const doc = await db.collection('posts').doc(req.params.id).get();
        if (!doc.exists) {
            const err = new Error('Post not found'); err.status = 404; return next(err);
        }

        const data = doc.data();
        if (data.visibility === 'shadow' && data.authorId !== req.user.uid) {
            const err = new Error('Post not found'); err.status = 404; return next(err);
        }

        let eventStart = safeParseIso(data.eventStartDate);
        let eventEnd = safeParseIso(data.eventEndDate);
        let computedGroupStatus = 'active';

        if (data.isEvent) {
            const fallback = safeParseIso(data.eventDate);
            if (!eventStart && fallback) eventStart = fallback;
            if (!eventEnd && eventStart) {
                try { eventEnd = new Date(new Date(eventStart).getTime() + 2 * 3600000).toISOString(); } catch { }
            }
            if (eventEnd) {
                try { if (new Date(eventEnd) < new Date()) computedGroupStatus = 'archived'; } catch { }
            }
        }

        const countDelta = INTERACTION_DELTAS.counts.get(doc.id) || 0;
        const { likedPostIds } = await getUserContext(req.user.uid);

        return res.json({
            success: true,
            data: {
                id: doc.id, ...data,
                eventStartDate: eventStart,
                eventEndDate: eventEnd,
                computedStatus: computedGroupStatus,
                isLiked: likedPostIds.has(doc.id),
                likeCount: (data.likeCount || 0) + countDelta,
                createdAt: safeParseIso(data.createdAt),
            },
            error: null
        });
    } catch (err) { next(err); }
});

// ============================================================
//  DELETE /api/posts/:id
// ============================================================
router.delete('/:id', authenticate, async (req, res, next) => {
    try {
        const postRef = db.collection('posts').doc(req.params.id);
        const doc = await postRef.get();
        if (!doc.exists) return res.status(404).json({ error: 'Post not found' });

        const data = doc.data();
        if (data.authorId !== req.user.uid && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Unauthorized' });
        }

        const batch = db.batch();
        batch.delete(postRef);

        if (data.isEvent) {
            const [groupSnap, memberSnap, attendanceSnap] = await Promise.all([
                db.collection('event_groups').where('eventId', '==', req.params.id).get(),
                db.collection('event_group_members').where('eventId', '==', req.params.id).get(),
                db.collection('event_attendance').where('eventId', '==', req.params.id).get()
            ]);
            groupSnap.docs.forEach(d => batch.delete(d.ref));
            memberSnap.docs.forEach(d => batch.delete(d.ref));
            attendanceSnap.docs.forEach(d => batch.delete(d.ref));
        }

        await batch.commit();
        await AuditService.logAction({
            userId: req.user.uid, action: 'POST_DELETED',
            metadata: { postId: req.params.id }, req
        });

        // Remove from RAM index
        geoIndex.remove(req.params.id);

        return res.json({ success: true, data: { message: 'Post deleted' }, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  POST /api/posts/:id/messages
// ============================================================
router.post('/:id/messages', authenticate, async (req, res, next) => {
    try {
        const { text } = cleanPayload(req.body, ['text']);
        if (!text) return res.status(400).json({ error: 'Message text required' });

        const senderName = buildDisplayName({
            displayName: req.user.displayName,
            email: req.user.email, fallback: 'User'
        });

        const messageData = {
            senderId: req.user.uid, senderName,
            senderProfileImage: req.user.photoURL,
            text, timestamp: admin.firestore.FieldValue.serverTimestamp()
        };

        const messageRef = await db.collection('posts')
            .doc(req.params.id).collection('messages').add(messageData);

        return res.status(201).json({ success: true, data: { id: messageRef.id, ...messageData }, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  GET /api/posts/:id/messages
// ============================================================
router.get('/:id/messages', authenticate, async (req, res, next) => {
    try {
        const snapshot = await db.collection('posts').doc(req.params.id)
            .collection('messages').orderBy('timestamp', 'desc').limit(100).get();

        const messages = snapshot.docs.map(doc => ({
            id: doc.id, ...doc.data(),
            timestamp: doc.data().timestamp?.toDate()?.toISOString()
        }));

        return res.json({ success: true, data: messages, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  POST /api/posts/:id/view
// ============================================================
router.post('/:id/view', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const userId = req.user.uid;

        const userDoc = await db.collection('users').doc(userId).get();
        const userData = userDoc.data();

        const viewData = {
            userId,
            userName: buildDisplayName({
                displayName: req.user.displayName,
                username: userData?.username,
                firstName: userData?.firstName,
                lastName: userData?.lastName,
                email: userData?.email || req.user.email, fallback: 'User'
            }),
            userAvatar: req.user.photoURL,
            location: userData?.city || null,
            viewedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection('posts').doc(postId).collection('views').doc(userId).set(viewData, { merge: true });
        await db.collection('posts').doc(postId).update({ viewCount: admin.firestore.FieldValue.increment(1) });

        return res.json({ success: true, data: { viewed: true }, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  GET /api/posts/:id/insights
// ============================================================
router.get('/:id/insights', authenticate, async (req, res, next) => {
    try {
        const postDoc = await db.collection('posts').doc(req.params.id).get();
        if (!postDoc.exists) return res.status(404).json({ success: false, error: 'Post not found' });

        const postData = postDoc.data();
        if (postData.authorId !== req.user.uid) {
            return res.status(403).json({ success: false, error: 'You can only view insights for your own posts' });
        }

        const viewsSnapshot = await db.collection('posts').doc(req.params.id)
            .collection('views').orderBy('viewedAt', 'desc').limit(100).get();

        const viewers = viewsSnapshot.docs.map(doc => ({
            ...doc.data(), viewedAt: doc.data().viewedAt?.toDate()?.toISOString()
        }));

        return res.json({ success: true, data: { viewCount: postData.viewCount || 0, viewers }, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  POST /api/posts/:id/report
// ============================================================
router.post('/:id/report', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const reporterId = req.user.uid;
        const { reason } = req.body;

        const validReasons = [
            'Spam or misleading', 'Harassment or hate speech',
            'Violence or dangerous content', 'Nudity or sexual content',
            'False information', 'Intellectual property violation', 'Something else'
        ];

        if (!reason || !validReasons.includes(reason)) {
            return res.status(400).json({ success: false, error: 'Invalid report reason' });
        }

        const postDoc = await db.collection('posts').doc(postId).get();
        if (!postDoc.exists) return res.status(404).json({ success: false, error: 'Post not found' });

        const postData = postDoc.data();
        if (postData.authorId === reporterId) {
            return res.status(400).json({ success: false, error: 'Cannot report your own post' });
        }

        const reportData = {
            postId, postAuthorId: postData.authorId, reporterId,
            reporterName: buildDisplayName({ displayName: req.user.displayName, email: req.user.email, fallback: 'User' }),
            reason, status: 'pending',
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            postTitle: postData.title || postData.body?.substring(0, 100) || 'Untitled',
            postMediaUrl: postData.mediaUrl || null
        };

        const reportRef = await db.collection('reports').add(reportData);
        await db.collection('posts').doc(postId).update({
            reportCount: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        const updatedPost = await db.collection('posts').doc(postId).get();
        if ((updatedPost.data().reportCount || 0) >= 5) {
            await db.collection('posts').doc(postId).update({
                visibility: 'flagged',
                flaggedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            logger.warn({ postId }, 'Post auto-flagged');
        }

        await AuditService.logAction({
            userId: reporterId, action: 'POST_REPORTED',
            metadata: { postId, reason, reportId: reportRef.id }, req
        });

        return res.json({ success: true, data: { reported: true, reportId: reportRef.id, postId }, error: null });
    } catch (err) { next(err); }
});

// ============================================================
//  HELPERS — Mentions & Notifications
// ============================================================
async function _processMentions(text, currentUserId) {
    if (!text) return [];
    const matches = [...text.matchAll(/@([a-zA-Z0-9._]+)/g)];
    if (!matches.length) return [];

    const usernames = [...new Set(matches.map(m => m[1].toLowerCase()))];
    const mentionUids = [];

    for (let i = 0; i < usernames.length; i += 10) {
        const chunk = usernames.slice(i, i + 10);
        const snap = await db.collection('users').where('username', 'in', chunk).limit(10).get();
        snap.docs.forEach(doc => {
            if (doc.id !== currentUserId) mentionUids.push(doc.id);
        });
    }

    return [...new Set(mentionUids)];
}

async function _sendNotificationInternal({ toUserId, fromUserId, fromUserName, fromUserProfileImage, type, postId, postThumbnail, commentText }) {
    if (!toUserId || toUserId === fromUserId) return;
    try {
        const notificationData = {
            toUserId, fromUserId,
            fromUserName: fromUserName || 'Someone',
            fromUserProfileImage: fromUserProfileImage || null,
            type, isRead: false,
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