/**
 * Posts Routes - REFACTORED VERSION
 * 
 * Architecture:
 * - Feed endpoints (GET /posts, POST /posts, DELETE, etc.) use new repository/service layers
 * - Legacy endpoints (messages, insights, report) preserved from old system
 * 
 * This hybrid approach:
 * ✅ Eliminates duplicate feed queries
 * ✅ Uses centralized pagination/sorting
 * ✅ Preserves critical legacy functionality
 * ✅ Enables gradual migration of remaining endpoints
 */

import express from 'express';
import postController from '../controllers/postController.js';
import authenticate from '../middleware/auth.js';
import { validateBody, validateQuery, validateParams, schemas } from '../middleware/validation.js';
import logger from '../utils/logger.js';
import { db } from '../config/firebase.js';
import admin from 'firebase-admin';
import { cleanPayload } from '../utils/sanitizer.js';
import { buildDisplayName } from '../utils/userDisplayName.js';
import AuditService from '../services/auditService.js';
import postRepository from '../repositories/postRepository.js';

const router = express.Router();

// ============================================================
// Session Management for Feed Deduplication
// ============================================================

const SESSION_SEEN = new Map();
const SESSION_EXPIRY = 2 * 60 * 60 * 1000;

function cleanupSessions() {
  const now = Date.now();
  for (const [sid, session] of SESSION_SEEN.entries()) {
    if (now - session.lastActive > SESSION_EXPIRY) {
      SESSION_SEEN.delete(sid);
    }
  }
}

// BUG-009 FIX: Periodic cleanup prevents memory leak when no new sessions are created
setInterval(cleanupSessions, 10 * 60 * 1000);

/**
 * Middleware to manage session seen IDs
 * 
 * CRITICAL: 
 * - Tracks seenIds PER FEED TYPE (local/global/filtered) to prevent tab contamination
 * - Detects URL length overflow (414 errors)
 * - When seenIds > 500, client should switch to POST-based pagination
 */
function sessionMiddleware(req, res, next) {
  const { sid, watchedIds, feedType = 'global' } = req.query;

  // Initialize per-feedType seenIds tracking
  if (sid) {
    if (!SESSION_SEEN.has(sid)) {
      cleanupSessions();
      // Store separate seenIds for each feed type
      SESSION_SEEN.set(sid, { 
        local: new Set(),
        global: new Set(),
        filtered: new Set(),
        lastActive: Date.now() 
      });
    }
    const sessionData = SESSION_SEEN.get(sid);
    sessionData.lastActive = Date.now();
    
    // Get seenIds for THIS feed type
    req.sessionSeenIds = sessionData[feedType] || new Set();
  } else {
    req.sessionSeenIds = new Set();
  }

  if (watchedIds) {
    try {
      const decodedIds = decodeURIComponent(watchedIds);
      const ids = decodedIds.split(',').filter(id => id.trim());
      
      // CRITICAL: Check URL length before adding more IDs
      const currentUrlLength = req.originalUrl.length;
      if (currentUrlLength > 2000) {
        logger.warn(
          { currentUrlLength, idCount: ids.length, feedType },
          '[Posts] URL length exceeded 2000 chars (414 risk) — client should use POST-based pagination'
        );
        // Cap at 500 IDs to prevent future 414 errors
        ids.slice(-500).forEach(id => req.sessionSeenIds.add(id.trim()));
      } else {
        ids.forEach(id => req.sessionSeenIds.add(id.trim()));
      }
    } catch (error) {
      logger.warn({ watchedIds, error }, '[Posts] Error parsing watchedIds');
    }
  }

  next();
}

// ============================================================
// REFACTORED FEED ENDPOINTS - Using Repository Layer
// ============================================================

/**
 * Create a new post
 * POST /api/posts
 */
router.post(
  '/',
  authenticate,
  validateBody(schemas.post),
  async (req, res, next) => {
    try {
      await postController.createPost(req, res, next);
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Posts] Create error');
      next(error);
    }
  }
);

  /**
   * Get posts (feed endpoint with routing to appropriate feed type)
   * GET /api/posts?feedType=local|global|hybrid|filtered&lat=X&lng=Y
   */
  router.get(
    '/',
    authenticate,
    sessionMiddleware,
    validateQuery(schemas.feedQuery),
    async (req, res, next) => {
      try {
        const { feedType, lat, lng, authorId, category, city, country } = req.query;

        // Route to appropriate feed
        if (feedType === 'hybrid' && lat && lng) {
          // MAIN FEED: Hybrid merge (local + global + dedup)
          return postController.getHybridFeed(req, res, next);
        } else if (feedType === 'local' && lat && lng) {
          // Geographic only
          return postController.getLocalFeed(req, res, next);
        } else if (authorId || category || city || country) {
          // Filtered
          return postController.getFilteredFeed(req, res, next);
        } else {
          // Default to global feed
          return postController.getGlobalFeed(req, res, next);
        }
      } catch (error) {
        logger.error({ error, uid: req.user?.uid }, '[Posts] Get feed error');
        next(error);
      }
    }
  );

  /**
   * Get explore grid content
   * GET /api/posts/explore
   */
  router.get(
    '/explore',
    authenticate,
    async (req, res, next) => {
      try {
        await postController.getExploreGrid(req, res, next);
      } catch (error) {
        logger.error({ error, uid: req.user?.uid }, '[Posts] Get explore error');
        next(error);
      }
    }
  );

// BUG-001 FIX: /new-since MUST be registered BEFORE /:id to prevent route shadowing
/**
 * GET /api/posts/new-since - Check for new posts since timestamp
 * TODO: Refactor to use repository layer
 */
router.get('/new-since', authenticate, async (req, res, next) => {
  try {
    const { since } = req.query;
    
    if (!since) {
      return res.status(400).json({
        success: false,
        error: 'Since timestamp required'
      });
    }

    const sinceDate = new Date(parseInt(since));
    const query = db.collection('posts')
      .where('visibility', '==', 'public')
      .where('status', '==', 'active')
      .where('createdAt', '>', sinceDate)
      .orderBy('createdAt', 'desc')
      .limit(50);

    const snapshot = await query.get();
    const posts = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));

    return res.json({
      success: true,
      data: posts,
      error: null
    });
  } catch (err) {
    next(err);
  }
});

/**
 * Get a single post by ID
 * GET /api/posts/:id
 */
router.get(
  '/:id',
  authenticate,
  async (req, res, next) => {
    try {
      await postController.getPost(req, res, next);
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Posts] Get single error');
      next(error);
    }
  }
);

/**
 * Update a post
 * PUT /api/posts/:id
 */
router.put(
  '/:id',
  authenticate,
  validateBody(schemas.post),
  async (req, res, next) => {
    try {
      await postController.updatePost(req, res, next);
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Posts] Update error');
      next(error);
    }
  }
);

/**
 * Delete a post
 * DELETE /api/posts/:id
 */
router.delete(
  '/:id',
  authenticate,
  async (req, res, next) => {
    try {
      await postController.deletePost(req, res, next);
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Posts] Delete error');
      next(error);
    }
  }
);

/**
 * Record a post view
 * POST /api/posts/:id/view
 */
router.post('/:id/view', authenticate, async (req, res, next) => {
  try {
    await postController.viewPost(req, res, next);
  } catch (err) {
    next(err);
  }
});

// ============================================================
// LEGACY ENDPOINTS - Refactored to Controller (BUG-028)
// ============================================================

/**
 * POST /api/posts/:id/messages - Add message to post
 * TODO: Move this specifically into interaction service or controller
 */
router.post('/:id/messages', authenticate, async (req, res, next) => {
  try {
    const { text } = cleanPayload(req.body, ['text']);
    if (!text) {
      return res.status(400).json({ error: 'Message text required' });
    }

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
 * GET /api/posts/:id/messages - Get messages for a post
 */
router.get('/:id/messages', authenticate, async (req, res, next) => {
  try {
    await postController.getEventChatMessages(req, res, next);
  } catch (err) {
    next(err);
  }
});

/**
 * GET /api/posts/:id/insights - Get post analytics
 */
router.get('/:id/insights', authenticate, async (req, res, next) => {
  try {
    await postController.getPostInsights(req, res, next);
  } catch (err) {
    next(err);
  }
});

/**
 * POST /api/posts/:id/report - Report a post
 */
router.post('/:id/report', authenticate, async (req, res, next) => {
  try {
    await postController.reportPost(req, res, next);
  } catch (err) {
    next(err);
  }
});


export default router;
