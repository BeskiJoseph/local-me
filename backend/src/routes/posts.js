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

// In-memory session tracking for 'seen' posts to minimize payload size
// Format: sessionId -> Set of postIds
const SESSION_SEEN = new Map();
const SESSION_EXPIRY = 2 * 60 * 60 * 1000; // 2 hour TTL

// Cleanup function to evict old sessions
function cleanupSessions() {
    const now = Date.now();
    for (const [sid, session] of SESSION_SEEN.entries()) {
        if (now - session.lastActive > SESSION_EXPIRY) {
            SESSION_SEEN.delete(sid);
        }
    }
}
import {
    getUserContext,
    updateUserContextCache,
    invalidateUserContext,
    USER_CONTEXT_CACHE,
    INTERACTION_DELTAS
} from '../services/userContextService.js';

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
//  N-GRAM GENERATOR FOR SUBSTRING SEARCH
//  Generates 3+ char substrings from title for array-contains queries
// ============================================================
function generateNgrams(text, minLen = 3) {
    if (!text) return [];
    const normalized = text.toLowerCase().trim();
    const tokens = new Set();

    // Sliding window n-grams over full string
    for (let i = 0; i < normalized.length; i++) {
        for (let len = minLen; len <= Math.min(normalized.length - i, 20); len++) {
            tokens.add(normalized.substring(i, i + len));
        }
    }

    // Per-word n-grams
    const words = normalized.split(/\s+/).filter(w => w.length >= minLen);
    for (const word of words) {
        for (let i = 0; i < word.length; i++) {
            for (let len = minLen; len <= Math.min(word.length - i, 15); len++) {
                tokens.add(word.substring(i, i + len));
            }
        }
    }

    // Cap at 100 tokens to keep Firestore doc size reasonable
    return Array.from(tokens).slice(0, 100);
}

// ============================================================
//  POST SCHEMA VALIDATION
// ============================================================
const postSchema = Joi.object({
    title: Joi.string().max(2000).allow(null, ''),
    body: Joi.string().max(5000).allow(null, ''),
    text: Joi.string().max(5000).allow(null, ''),
    category: Joi.string().max(50).allow(null, ''),
    city: Joi.string().max(100).allow(null, ''),
    country: Joi.string().max(100).allow(null, ''),
    mediaUrl: Joi.string().uri().allow(null, ''),
    mediaType: Joi.string().valid('image', 'video', 'text', 'document', 'none').default('none'),
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
const FETCH_LOCKS = new Map();
const LOCAL_POOL_CACHE = new Map(); // Cell-based cache for local document pools
const CACHE_TTL = 60 * 1000;        // 60s for author/category queries
const LOCAL_CACHE_TTL = 60 * 1000;   // 60s for cell-based local pool
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

// (Moved User Context logic to src/services/userContextService.js)
export const invalidateFeedCache = () => { 
    FEED_CACHE.clear(); 
    LOCAL_POOL_CACHE.clear();
    logger.debug('[CACHE] Global and Local feed caches cleared');
};

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

// (Moved getUserContext to src/services/userContextService.js)

// ============================================================
//  LOCAL FEED ENGINE ( seenIds-based )
// ============================================================
export async function fetchLocalFeedWithCursor(
    lat, lng,
    watchedIdsSet, pageSize,
    mediaType = null
) {
    const startTime = Date.now();
    const userLat = parseFloat(lat);
    const userLng = parseFloat(lng);

    // 1. Query RAM Index for exact distance matches
    logger.info({ userLat, userLng, pageSize, watchedCount: watchedIdsSet.size }, '[LOCAL FEED] Querying GeoIndex RAM');
    const searchResult = geoIndex.queryLocal(userLat, userLng, watchedIdsSet, mediaType, pageSize);
    const candidates = searchResult.posts;
    const maxScanned = searchResult.maxScannedDistance;

    if (candidates.length === 0) {
        logger.info('[LOCAL FEED] All posts seen. Triggering "Cycle" fallback.');
        const cycleResult = geoIndex.queryLocal(userLat, userLng, new Set(), mediaType, pageSize);
        const cycleCandidates = cycleResult.posts;
        
        if (cycleCandidates.length === 0) {
            return { success: true, posts: [], hasMore: false, maxScannedDistance: 0 };
        }

        const cycleDocs = await Promise.all(
            cycleCandidates.map(c => db.collection('posts').doc(c.id).get())
        );

        const cyclePage = cycleDocs
            .filter(d => d.exists)
            .map(d => {
                const idxData = cycleCandidates.find(c => c.id === d.id);
                return { ...mapDocToPost(d), distance: idxData ? idxData.distance : 0 };
            });

        return {
            success: true,
            posts: cyclePage,
            hasMore: true, // 🥇 Fix 2: Cycle always has more potential content
            maxScannedDistance: cyclePage.length > 0 ? cyclePage[cyclePage.length - 1].distance : 0
        };
    }

    // 2. Fetch full Post documents from Firestore concurrently
    const firestoreStartTime = Date.now();
    const docs = await Promise.all(
        candidates.map(c => db.collection('posts').doc(c.id).get())
    );
    const firestoreMs = Date.now() - firestoreStartTime;

    const page = docs
        .filter(d => d.exists)
        .map(d => {
            const idxData = candidates.find(c => c.id === d.id);
            const post = mapDocToPost(d);
            return {
                ...post,
                distance: idxData ? idxData.distance : 0
            };
        });

    const lastPost = page[page.length - 1];
    const totalMs = Date.now() - startTime;

    logger.info({
        firestoreMs, totalMs, poolSize: geoIndex.size, returned: page.length,
        hasMore: searchResult.hasMore
    }, '[LOCAL FEED] Request complete');

    return {
        success: true,
        posts: page,
        hasMore: searchResult.hasMore,
        maxScannedDistance: maxScanned
    };
}

/**
 * GET /api/posts/new-since
 * Poll for new posts created after a certain timestamp
 */
router.get('/new-since', authenticate, async (req, res, next) => {
    try {
        const { lat, lng, city, sinceTimestamp, maxDistance, watchedIds, sid, mediaType } = req.query;
        if (!sinceTimestamp) {
            return res.status(400).json({ success: false, error: 'Missing sinceTimestamp' });
        }

        const since = new Date(parseInt(sinceTimestamp));
        const userLat = lat ? parseFloat(lat) : null;
        const userLng = lng ? parseFloat(lng) : null;
        const discoveryRadius = parseFloat(maxDistance) || 10;

        let sessionSet = new Set();
        if (sid) {
            if (!SESSION_SEEN.has(sid)) {
                SESSION_SEEN.set(sid, { ids: new Set(), lastActive: Date.now() });
            }
            const sessionData = SESSION_SEEN.get(sid);
            sessionData.lastActive = Date.now();
            sessionSet = sessionData.ids;
        }

        const decodedWatchedIds = watchedIds ? decodeURIComponent(watchedIds) : null;
        if (decodedWatchedIds) {
            decodedWatchedIds.split(',').forEach(id => {
                if (id.trim()) sessionSet.add(id.trim());
            });
        }

        const snapshot = await db.collection('posts')
            .where('visibility', '==', 'public')
            .where('status', '==', 'active')
            .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(since))
            .orderBy('createdAt', 'desc')
            .limit(50)
            .get();

        let newPosts = snapshot.docs
            .map(mapDocToPost)
            .map(post => ({
                ...post,
                distance: (userLat && userLng) ? getDistance(userLat, userLng, post.latitude, post.longitude) : null
            }))
            .filter(post => {
                if (sessionSet.has(post.id)) return false;
                if (mediaType && post.mediaType !== mediaType) return false;

                if (city) {
                    return post.city === city;
                } else if (userLat && userLng) {
                    return post.distance != null && post.distance <= discoveryRadius;
                }
                return false;
            });

        newPosts.sort((a, b) => (a.distance || 0) - (b.distance || 0));

        return res.json({
            success: true,
            data: newPosts,
            count: newPosts.length
        });
    } catch (error) { next(error); }
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
            err.status = 400; return next(err);
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
            geoHash = ngeohash.encode(value.location.lat, value.location.lng, 9);
        }

        const postData = {
            ...value,
            authorId: uid,
            authorName: actorDisplayName,
            authorProfileImage: req.user.photoURL,
            engagementScore: 0,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            likeCount: 0,
            commentCount: 0,
            viewCount: 0,
            visibility: isShadowBanned ? 'shadow' : 'public',
            status: 'active',
            geoHash,
            title_lowercase: (value.title || '').toLowerCase(),
            body_lowercase: (value.body || value.text || '').toLowerCase(),
            authorName_lowercase: (actorDisplayName || '').toLowerCase(),
            titleNgrams: generateNgrams(value.title || '')
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

        geoIndex.add(postRef.id, postData);
        invalidateFeedCache();

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
    const feedStartTime = Date.now();
    try {
        const {
            authorId, category, city, lat, lng, country,
            feedType, limit = 20, afterId,
            watchedIds, mediaType, sid
        } = req.query;

        // ── Session Matching ──
        let sessionSet = new Set();
        if (sid) {
            if (!SESSION_SEEN.has(sid)) {
                cleanupSessions(); // Run cleanup when a new session is born
                SESSION_SEEN.set(sid, { ids: new Set(), lastActive: Date.now() });
            }
            const sessionData = SESSION_SEEN.get(sid);
            sessionData.lastActive = Date.now();
            sessionSet = sessionData.ids;
        }

        // Explicitly decode URL-encoded commas if they managed to sneak through
        const decodedWatchedIds = watchedIds ? decodeURIComponent(watchedIds) : null;
        if (decodedWatchedIds) {
            decodedWatchedIds.split(',').forEach(id => {
                if (id.trim()) sessionSet.add(id.trim());
            });
        }

        const isLocalFeed = feedType === 'local';
        const pageSize = Math.min(parseInt(limit), 50);
        const { uid } = req.user;

        logger.info({ feedType, lat, lng, uid }, '[FEED] Request');


        // ── LOCAL FEED: Use seenIds-only engine (no distance cursor) ──
        // Only trigger local feed when lat/lng present and not a specific author query
        if (isLocalFeed && lat && lng && !authorId && !category) {

            const [responseData, userContext] = await Promise.all([
                fetchLocalFeedWithCursor(
                    lat, lng,
                    sessionSet, // Use the persistent session set
                    pageSize,
                    mediaType
                ),
                getUserContext(uid)
            ]);
            // Normalize to a common shape
            let postsFromResponse = (responseData.posts || responseData.data || []);
            
            // ✅ RESILIENCY FIX: If Local (Distance) results are insufficient, 
            // fallback to a City-based query for the same area.
            if (postsFromResponse.length < pageSize && (city || country)) {
                logger.info('[FEED] Local GeoIndex results insufficient. Filling from City/Country.');
                let cityQuery = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active');
                
                if (city) cityQuery = cityQuery.where('city', '==', city);
                else if (country) cityQuery = cityQuery.where('country', '==', country);
                
                if (mediaType) cityQuery = cityQuery.where('mediaType', '==', mediaType);
                
                const citySnapshot = await cityQuery.orderBy('createdAt', 'desc').limit(pageSize).get();
                const cityPosts = citySnapshot.docs.map(mapDocToPost);
                
                const postMap = new Map();
                postsFromResponse.forEach(p => postMap.set(p.id, p));
                cityPosts.forEach(p => {
                    if (!postMap.has(p.id)) postMap.set(p.id, p);
                });
                postsFromResponse = Array.from(postMap.values()).slice(0, pageSize);
            }

            let finalPosts = postsFromResponse.filter(
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

            // ✅ Fix 1: Strictly REMOVED automatic seen marking in backend.
            // Result: Only posts actually viewed in frontend enter the seenIds filter.

            return res.json({
                success: true,
                data: finalPosts,
                hasMore: responseData.hasMore || finalPosts.length >= pageSize // ✅ Fix 3: Safer hasMore
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

        const isFilteredQuery = !!(authorId || category || (!isLocalFeed && feedType !== 'global' && (city || country)));
        const cacheKey = isFilteredQuery
            ? `feed:filtered:${authorId || ''}:${category || ''}:${city || ''}:${mediaType || ''}:${pageSize}:${afterId || 'p1'}`
            : `feed:global:trending:${mediaType || ''}:${pageSize}:${afterId || 'p1'}`;

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
                    if (country) query = query.where('country', '==', country);
                    if (mediaType) query = query.where('mediaType', '==', mediaType);

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

                // ── Global trending feed — native engagement ranking ──
                let trendingQuery = db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active');

                if (mediaType) {
                    trendingQuery = trendingQuery.where('mediaType', '==', mediaType);
                }

                // Apply Cursor for Trending
                if (afterId) {
                    const lastDoc = await db.collection('posts').doc(afterId).get();
                    if (lastDoc.exists) {
                        // Note: In Trending sessions, cursors are tricky because engagement scores change.
                        // For simplicity, we fallback to recent if afterId is present or use a standardized cursor.
                        trendingQuery = trendingQuery.orderBy('engagementScore', 'desc').startAfter(lastDoc);
                    } else {
                        trendingQuery = trendingQuery.orderBy('engagementScore', 'desc');
                    }
                } else {
                    trendingQuery = trendingQuery.orderBy('engagementScore', 'desc');
                }

                const trendingSnapshot = await trendingQuery.limit(pageSize).get();
                let posts = trendingSnapshot.docs.map(mapDocToPost);

                // ✅ RESILIENCY FIX: If trending returns nothing (e.g. scores missing or cursor offset),
                // fallback to most recent posts.
                if (posts.length < pageSize) {
                    logger.info('[FEED] Trending results insufficient. Filling from Recency.');
                    let recentQuery = db.collection('posts')
                        .where('visibility', '==', 'public')
                        .where('status', '==', 'active');
                    
                    if (mediaType) recentQuery = recentQuery.where('mediaType', '==', mediaType);
                    recentQuery = recentQuery.orderBy('createdAt', 'desc');

                    if (afterId) {
                        const lastDoc = await db.collection('posts').doc(afterId).get();
                        if (lastDoc.exists) recentQuery = recentQuery.startAfter(lastDoc);
                    }
                    
                    const recentSnapshot = await recentQuery.limit(pageSize).get();
                    const recentPosts = recentSnapshot.docs.map(mapDocToPost);
                    
                    const postMap = new Map();
                    posts.forEach(p => postMap.set(p.id, p));
                    recentPosts.forEach(p => {
                        if (!postMap.has(p.id)) postMap.set(p.id, p);
                    });
                    posts = Array.from(postMap.values()).slice(0, pageSize);
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

            FETCH_LOCKS.set(cacheKey, responseDataPromise);
            responseDataPromise.then(data => {
                FEED_CACHE.set(cacheKey, { timestamp: Date.now(), data });
                FETCH_LOCKS.delete(cacheKey);
            }).catch(() => FETCH_LOCKS.delete(cacheKey));
        }

        // ── Step 2: Decorate with User Context (Muted / Likes / Follows) ──
        const [resolvedData, userContext] = await Promise.all([
            responseDataPromise,
            getUserContext(uid)
        ]);

        if (!resolvedData?.success) {
            return res.json({ success: false, data: [], error: resolvedData?.error || 'Feed generation failed' });
        }

        const watchedIdsSet = decodedWatchedIds
            ? new Set(decodedWatchedIds.split(',').map(id => id.trim()).filter(Boolean))
            : new Set();

        let finalPosts = (resolvedData.data || []).filter(
            post => !userContext.mutedUserIds.has(post.authorId) && !sessionSet.has(post.id)
        );

        let fallbackLevel = 1;

        // ✅ Fix 4: If all results are filtered out, return the raw data as a fallback 
        // to prevent the feed from showing "no content" prematurely.
        if (finalPosts.length === 0 && (resolvedData.data || []).length > 0) {
            logger.info('[GLOBAL FEED] All cached posts seen. Cycling back.');
            finalPosts = resolvedData.data;
            fallbackLevel = 'cycle';
        }

        // ✅ Fix 1: Removed automatic seen marking in backend for Global feed too.
        /*
        if (sid && finalPosts.length > 0) {
            const session = SESSION_SEEN.get(sid);
            if (session) {
                finalPosts.forEach(p => session.ids.add(p.id));
            }
        }
        */

        finalPosts = finalPosts.map(post => {
            const countDelta = INTERACTION_DELTAS.counts.get(post.id) || 0;
            const isFollowing = userContext.followedUserIds.has(post.authorId);
            return {
                ...post,
                isLiked: userContext.likedPostIds.has(post.id),
                isFollowing,
                likeCount: (post.likeCount || 0) + countDelta,
                engagementScore: post.engagementScore
            };
        });

        logger.info({ feedMs: Date.now() - feedStartTime }, '[FEED] Request complete');
        return res.json({
            success: true,
            data: finalPosts,
            pagination: {
                ...(resolvedData.pagination || {}),
                hasMore: (resolvedData.pagination?.hasMore || finalPosts.length >= pageSize),
                fallbackLevel: fallbackLevel
            },
            error: null
        });

    } catch (err) {
        logger.error({ feedMs: Date.now() - feedStartTime, err: err.message }, '[FEED] Request error');
        return next(err);
    }
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
//  PATCH /api/posts/:id — Update Post
// ============================================================
router.patch('/:id', authenticate, async (req, res, next) => {
    try {
        const postId = req.params.id;
        const { uid } = req.user;
        const postRef = db.collection('posts').doc(postId);
        const doc = await postRef.get();

        if (!doc.exists) {
            return res.status(404).json({ success: false, error: 'Post not found' });
        }

        const currentData = doc.data();
        if (currentData.authorId !== uid && req.user.role !== 'admin') {
            return res.status(403).json({ success: false, error: 'Unauthorized' });
        }

        const ALLOWED_UPDATE_FIELDS = [
            'title', 'body', 'text', 'category', 'city', 'country',
            'mediaUrl', 'mediaType', 'thumbnailUrl', 'location',
            'tags', 'isEvent', 'eventStartDate', 'eventEndDate', 'eventDate',
            'eventLocation', 'isFree', 'eventType', 'subtitle'
        ];
        const cleanUpdates = cleanPayload(req.body, ALLOWED_UPDATE_FIELDS);

        // Use postSchema for validation (allowing partials as per Joi default in this context)
        const { error, value } = postSchema.validate(cleanUpdates, { allowUnknown: true });
        if (error) {
            const err = new Error(error.details[0].message);
            err.status = 400;
            return next(err);
        }

        const updateData = {
            ...value,
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        if (value.title !== undefined) {
            updateData.title_lowercase = value.title.toLowerCase();
            updateData.titleNgrams = generateNgrams(value.title);
        }
        if (value.body !== undefined || value.text !== undefined) {
            updateData.body_lowercase = (value.body || value.text || '').toLowerCase();
        }

        let newGeoHash = null;
        if (value.location?.lat && value.location?.lng) {
            newGeoHash = ngeohash.encode(value.location.lat, value.location.lng, 9);
            updateData.geoHash = newGeoHash;
        }

        await postRef.update(updateData);

        // Update RAM index if location or data changed
        geoIndex.update(postId, updateData);
        invalidateFeedCache();

        await AuditService.logAction({
            userId: uid, action: 'POST_UPDATED',
            metadata: { postId, updates: Object.keys(value) }, req
        });

        return res.json({
            success: true,
            data: { id: postId, ...updateData, updatedAt: new Date().toISOString() },
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

        // Invalidate caches and RAM index
        geoIndex.remove(req.params.id);
        invalidateFeedCache();

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

        // Check if user already viewed this post (prevent count inflation)
        const viewRef = db.collection('posts').doc(postId).collection('views').doc(userId);
        const existingView = await viewRef.get();
        const isFirstView = !existingView.exists;

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

        await viewRef.set(viewData, { merge: true });

        // Only increment viewCount on first view by this user
        if (isFirstView) {
            await db.collection('posts').doc(postId).update({ viewCount: admin.firestore.FieldValue.increment(1) });
        }

        return res.json({ success: true, data: { viewed: true, firstView: isFirstView }, error: null });
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
