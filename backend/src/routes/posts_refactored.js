/**
 * Posts Routes - Refactored with clean 3-layer architecture
 * 
 * BEFORE: Routes directly queried Firestore with scattered logic
 * AFTER: Routes use PostController which uses FeedService which uses PostRepository
 * 
 * Benefits:
 * - No duplicate Firestore queries
 * - Consistent sorting and pagination
 * - Centralized business logic
 * - Easy to test and maintain
 */

import express from 'express';
import postController from '../controllers/postController.js';
import authenticate from '../middleware/auth.js';
import { validateBody, validateQuery, validateParams, schemas } from '../middleware/validation.js';
import logger from '../utils/logger.js';

const router = express.Router();

// ============================================================
// Session Management for Feed Deduplication
// ============================================================

// In-memory session tracking for 'seen' posts
const SESSION_SEEN = new Map();
const SESSION_EXPIRY = 2 * 60 * 60 * 1000; // 2 hour TTL

/**
 * Cleanup old session data
 */
function cleanupSessions() {
  const now = Date.now();
  for (const [sid, session] of SESSION_SEEN.entries()) {
    if (now - session.lastActive > SESSION_EXPIRY) {
      SESSION_SEEN.delete(sid);
    }
  }
}

/**
 * Middleware to attach session data to request
 */
function sessionMiddleware(req, res, next) {
  const { sid, watchedIds } = req.query;

  // Initialize session if needed
  if (sid) {
    if (!SESSION_SEEN.has(sid)) {
      cleanupSessions();
      SESSION_SEEN.set(sid, { ids: new Set(), lastActive: Date.now() });
    }
    const sessionData = SESSION_SEEN.get(sid);
    sessionData.lastActive = Date.now();

    // Attach to request for controller use
    req.sessionSeenIds = sessionData.ids;
  } else {
    req.sessionSeenIds = new Set();
  }

  // Add watchedIds from query if provided
  if (watchedIds) {
    try {
      const decodedIds = decodeURIComponent(watchedIds);
      decodedIds.split(',').forEach(id => {
        if (id.trim()) req.sessionSeenIds.add(id.trim());
      });
    } catch (error) {
      logger.warn({ watchedIds, error }, '[Posts] Error parsing watchedIds');
    }
  }

  next();
}

// ============================================================
// POST ENDPOINTS
// ============================================================

/**
 * Create a new post
 * POST /posts
 */
router.post(
  '/',
  authenticate,
  validateBody(schemas.post),
  async (req, res, next) => {
    try {
      await postController.createPost(req, res, next);
    } catch (error) {
      logger.error({ error }, '[Posts] Create error');
      next(error);
    }
  }
);

/**
 * Get a single post by ID
 * GET /posts/:id
 */
router.get(
  '/:id',
  authenticate,
  async (req, res, next) => {
    try {
      await postController.getPost(req, res, next);
    } catch (error) {
      logger.error({ error }, '[Posts] Get single error');
      next(error);
    }
  }
);

/**
 * Get feed (local, global, or filtered)
 * GET /posts?feedType=local|global|filtered&lat=X&lng=Y&limit=20&afterId=...
 * 
 * Query Parameters:
 * - feedType: 'local' (geo), 'global' (trending), 'filtered' (author/category/city)
 * - lat, lng: Required for local feed
 * - limit: 1-50 (default 20)
 * - afterId: Last post ID for pagination
 * - mediaType: Filter by media type
 * - authorId, category, city, country: For filtered feed
 * - sid: Session ID for tracking seen posts
 * - watchedIds: Comma-separated post IDs already shown to user
 */
router.get(
  '/',
  authenticate,
  sessionMiddleware,
  validateQuery(schemas.feedQuery),
  async (req, res, next) => {
    try {
      const { feedType, lat, lng, authorId, category, city, country } = req.query;

      // Route to appropriate feed endpoint
      if (feedType === 'local' && lat && lng) {
        return postController.getLocalFeed(req, res, next);
      } else if (authorId || category || city || country) {
        return postController.getFilteredFeed(req, res, next);
      } else {
        // Default to global feed
        return postController.getGlobalFeed(req, res, next);
      }
    } catch (error) {
      logger.error({ error }, '[Posts] Get feed error');
      next(error);
    }
  }
);

/**
 * Update a post
 * PUT /posts/:id
 */
router.put(
  '/:id',
  authenticate,
  validateBody(schemas.post),
  async (req, res, next) => {
    try {
      await postController.updatePost(req, res, next);
    } catch (error) {
      logger.error({ error }, '[Posts] Update error');
      next(error);
    }
  }
);

/**
 * Delete a post
 * DELETE /posts/:id
 */
router.delete(
  '/:id',
  authenticate,
  async (req, res, next) => {
    try {
      await postController.deletePost(req, res, next);
    } catch (error) {
      logger.error({ error }, '[Posts] Delete error');
      next(error);
    }
  }
);

/**
 * Record a post view
 * POST /posts/:id/view
 */
router.post(
  '/:id/view',
  authenticate,
  async (req, res, next) => {
    try {
      await postController.viewPost(req, res, next);
    } catch (error) {
      logger.error({ error }, '[Posts] View error');
      next(error);
    }
  }
);

// ============================================================
// LEGACY ENDPOINTS (TO BE REFACTORED)
// ============================================================
// These endpoints are preserved from the old posts.js for compatibility
// They will be refactored in subsequent iterations

/**
 * Placeholder for /new-since endpoint
 * This endpoint checks for new posts since a given timestamp
 * TO DO: Refactor using repository layer
 */
router.get('/new-since', authenticate, async (req, res, next) => {
  try {
    // TODO: Implement using postRepository
    return res.json({
      success: true,
      data: [],
      message: 'new-since endpoint pending refactor to repository layer'
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Placeholder for /insights endpoint
 * TO DO: Refactor using repository layer
 */
router.get('/:id/insights', authenticate, async (req, res, next) => {
  try {
    // TODO: Implement using postRepository
    return res.json({
      success: true,
      data: {},
      message: 'insights endpoint pending refactor to repository layer'
    });
  } catch (error) {
    next(error);
  }
});

export default router;
