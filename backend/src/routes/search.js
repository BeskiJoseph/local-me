import express from 'express';
import admin, { db } from '../config/firebase.js';
import authenticate from '../middleware/auth.js';
import MetricsService from '../services/metricsService.js';
import logger from '../utils/logger.js';

const router = express.Router();

// ─────────────────────────────────────────────
//  Phase 1 Ranking Config
// ─────────────────────────────────────────────
const RANKING_WEIGHTS = {
    textMatch: 0.5,
    likes: 0.15,
    comments: 0.2,
    views: 0.1,
    recency: 0.05
};

// ─────────────────────────────────────────────
//  Search Cache with LRU eviction
// ─────────────────────────────────────────────
const _searchCache = new Map();
const SEARCH_CACHE_TTL = 60 * 1000;
const SEARCH_CACHE_MAX = 200;

function cacheSet(key, data) {
    if (_searchCache.size >= SEARCH_CACHE_MAX) {
        const keysToDelete = [..._searchCache.keys()].slice(0, 50);
        keysToDelete.forEach(k => _searchCache.delete(k));
    }
    _searchCache.set(key, { timestamp: Date.now(), data });
}

function cacheGet(key) {
    const cached = _searchCache.get(key);
    if (cached && (Date.now() - cached.timestamp < SEARCH_CACHE_TTL)) {
        return cached.data;
    }
    if (cached) _searchCache.delete(key);
    return null;
}

// ─────────────────────────────────────────────
//  Field allowlist
// ─────────────────────────────────────────────
const USER_SAFE_FIELDS = ['id', 'username', 'displayName', 'firstName', 'lastName', 'about', 'profileImageUrl', 'subscribers', 'city', 'country'];
const POST_SAFE_FIELDS = ['id', 'title', 'body', 'text', 'authorId', 'authorName', 'authorProfileImage', 'category', 'mediaUrl', 'mediaType', 'thumbnailUrl', 'likeCount', 'commentCount', 'viewCount', 'createdAt', 'city', 'country', 'isEvent', 'eventStartDate', 'eventEndDate', 'eventLocation', 'eventType', 'isFree', 'latitude', 'longitude', 'isLiked'];

function stripFields(obj, allowedFields) {
    const result = {};
    for (const key of allowedFields) {
        if (obj[key] !== undefined) result[key] = obj[key];
    }
    return result;
}

// ─────────────────────────────────────────────
//  Engagement-Weighted Ranking
// ─────────────────────────────────────────────
function calculateFinalScore(item, searchTerm, fieldNames) {
    if (!Array.isArray(fieldNames)) fieldNames = [fieldNames];
    
    // 1. Text Match Score (0.0 - 1.0) - Use the best match across all provided fields
    let bestTextScore = 0.01; // Base score
    
    for (const fieldName of fieldNames) {
        const value = (item[fieldName] || '').toLowerCase();
        let fieldScore = 0.0;
        if (value === searchTerm) fieldScore = 1.0;
        else if (value.startsWith(searchTerm)) fieldScore = 0.6; // Slightly boosted prefix
        else if (value.includes(searchTerm)) fieldScore = 0.2;
        
        if (fieldScore > bestTextScore) bestTextScore = fieldScore;
    }
    
    const textScore = bestTextScore;

    // 2. Engagement Scores
    const likesScore = Math.log1p(item.likeCount || 0);
    const commentsScore = Math.log1p(item.commentCount || 0);
    const viewsScore = Math.log1p(item.viewCount || 0);

    // 3. Recency Score
    let recencyScore = 0;
    if (item.createdAt) {
        const createdDate = item.createdAt._seconds ? new Date(item.createdAt._seconds * 1000) : new Date(item.createdAt);
        const ageInHours = (Date.now() - createdDate.getTime()) / (1000 * 60 * 60);
        recencyScore = 1 / (1 + ageInHours);
    }

    // 4. Weighted Total
    return (textScore * RANKING_WEIGHTS.textMatch) +
           (likesScore * RANKING_WEIGHTS.likes) +
           (commentsScore * RANKING_WEIGHTS.comments) +
           (viewsScore * RANKING_WEIGHTS.views) +
           (recencyScore * RANKING_WEIGHTS.recency);
}

function rankAndPaginate(results, searchTerm, fieldNames, limit, afterId) {
    // Score all results
    const scoredResults = results.map(item => ({
        ...item,
        _searchScore: calculateFinalScore(item, searchTerm, fieldNames)
    }));

    // Sort by score descending
    scoredResults.sort((a, b) => b._searchScore - a._searchScore);

    // Pagination logic
    let startIndex = 0;
    if (afterId) {
        startIndex = scoredResults.findIndex(r => r.id === afterId) + 1;
    }

    const paginatedResults = scoredResults.slice(startIndex, startIndex + limit);
    const lastResult = paginatedResults[paginatedResults.length - 1];
    const nextCursor = (startIndex + paginatedResults.length < scoredResults.length) ? lastResult.id : null;

    return {
        items: paginatedResults.map(({ _searchScore, ...rest }) => rest), // Strip internal score
        nextCursor
    };
}

// ─────────────────────────────────────────────
//  Search Event Logging
// ─────────────────────────────────────────────
function _logSearchEvent(userId, query, type, resultsCount) {
    db.collection('search_events').add({
        query: query,
        userId: userId,
        type: type,
        resultsCount: resultsCount,
        timestamp: admin.firestore.FieldValue.serverTimestamp()
    }).catch(err => logger.error({ err: err.message }, '[SEARCH_STATS] Log failed'));
}

/**
 * @route   GET /api/search
 * @desc    Search for users, posts, or both
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const { q, type = 'all', limit = 20, afterId } = req.query;
        if (!q || q.trim().length < 1) return res.json({ success: true, data: { users: [], posts: [], nextCursor: null }, error: null });

        const searchTerm = q.trim().toLowerCase();
        const pageSize = Math.min(parseInt(limit), 50);

        const cacheKey = `search:${type}:${searchTerm}:${pageSize}:${afterId || ''}`;
        const cached = cacheGet(cacheKey);
        if (cached) return res.json({ success: true, data: cached, error: null });

        const response = { nextCursor: null };

        // ─── User Search ───
        if (type === 'users' || type === 'all') {
            const userQueries = [
                db.collection('users').where('username', '>=', searchTerm).where('username', '<=', searchTerm + '\uf8ff').limit(100),
                db.collection('users').where('displayName_lowercase', '>=', searchTerm).where('displayName_lowercase', '<=', searchTerm + '\uf8ff').limit(100),
                db.collection('users').where('firstName_lowercase', '>=', searchTerm).where('firstName_lowercase', '<=', searchTerm + '\uf8ff').limit(100),
            ];

            const userSnaps = await Promise.all(userQueries.map(q => 
                q.get().catch(err => {
                    logger.warn({ err: err.message, query: q._queryOptions }, '[SEARCH] User query failed');
                    return { docs: [] };
                })
            ));
            
            const userMap = new Map();
            userSnaps.forEach(snap => snap.docs.forEach(doc => {
                if (!userMap.has(doc.id)) {
                    userMap.set(doc.id, stripFields({ id: doc.id, ...doc.data() }, USER_SAFE_FIELDS));
                }
            }));

            const { items, nextCursor } = rankAndPaginate(Array.from(userMap.values()), searchTerm, ['username', 'displayName', 'firstName'], pageSize, afterId);
            response.users = items;
            if (type === 'users') response.nextCursor = nextCursor;
        }

        // ─── Post Search ───
        if (type === 'posts' || type === 'all') {
            const postQueries = [];
            const isShort = searchTerm.length < 3;

            if (!isShort) {
                // Ngram search (only for 3+ chars)
                postQueries.push(db.collection('posts')
                    .where('visibility', '==', 'public')
                    .where('status', '==', 'active')
                    .where('titleNgrams', 'array-contains', searchTerm)
                    .limit(100));
            }

            // Range queries
            const buildRangeQuery = (field) => {
                let query = db.collection('posts');
                // Avoid composite indices for short queries by filtering in-memory later
                if (!isShort) {
                    query = query.where('visibility', '==', 'public').where('status', '==', 'active');
                }
                return query.where(field, '>=', searchTerm).where(field, '<=', searchTerm + '\uf8ff').limit(100);
            };

            postQueries.push(buildRangeQuery('title_lowercase'));
            postQueries.push(buildRangeQuery('body_lowercase'));
            postQueries.push(buildRangeQuery('authorName_lowercase'));

            const postSnaps = await Promise.all(postQueries.map(q => 
                q.get().catch(err => {
                    logger.warn({ err: err.message, query: q._queryOptions }, '[SEARCH] Post query failed');
                    return { docs: [] };
                })
            ));

            const postMap = new Map();
            postSnaps.forEach(snap => snap.docs.forEach(doc => {
                if (!postMap.has(doc.id)) {
                    const data = doc.data();
                    // Manual filter for short queries to ensure privacy without needing complex indices
                    if (isShort) {
                        if (data.visibility !== 'public' || data.status !== 'active') return;
                    }
                    postMap.set(doc.id, stripFields({ id: doc.id, ...data }, POST_SAFE_FIELDS));
                }
            }));

            const { items, nextCursor } = rankAndPaginate(Array.from(postMap.values()), searchTerm, ['title', 'body', 'authorName'], pageSize, afterId);
            response.posts = items;
            if (type === 'posts') response.nextCursor = nextCursor;
        }

        cacheSet(cacheKey, response);

        if (q.length >= 2) {
            const resultsCount = (response.users?.length || 0) + (response.posts?.length || 0);
            MetricsService.track('searches');
            _logSearchEvent(req.user.uid, q, type, resultsCount);
        }

        return res.json({ success: true, data: response, error: null });
    } catch (err) {
        logger.error({ err: err.message }, '[SEARCH] Fatal Error');
        next(err);
    }
});

export default router;
