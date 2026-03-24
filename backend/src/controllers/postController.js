/**
 * Post Controller - HTTP request/response handling layer
 * 
 * Coordinates between:
 * - HTTP requests (validation, parsing)
 * - FeedService (business logic)
 * - HTTP responses (formatting, error handling)
 * 
 * This controller extracts all business logic from routes.js
 * Routes now only handle HTTP mechanics.
 */

import feedService from '../services/feedService.js';
import postRepository from '../repositories/postRepository.js';
import geoService from '../services/geoService.js';
import { calculateGeohash, getGeohashBounds, getGeohashBoundsFromCoordinates } from '../utils/geohashHelper.js';
import {
  getUserContext,
  updateUserContextCache,
  INTERACTION_DELTAS
} from '../services/userContextService.js';
import logger from '../utils/logger.js';
import admin from 'firebase-admin';

class PostController {
  /**
   * Create a new post
   */
  async createPost(req, res, next) {
    try {
      const { uid } = req.user;
      const {
        title, body, city, country, latitude, longitude, mediaType,
        mediaUrl, visibility, status, category, geoHash
      } = req.body;

      // Create post
      const post = await postRepository.createPost({
        title,
        body,
        city,
        country,
        latitude,
        longitude,
        geoHash,
        mediaType,
        mediaUrl,
        visibility,
        status,
        category,
        authorId: uid,
        authorName: req.user.displayName || 'User',
        authorProfileImage: req.user.photoURL || null,
        likeCount: 0,
        commentCount: 0,
        viewCount: 0,
        engagementScore: 0
      });

      logger.info({ postId: post.id, uid }, '[Controller] Post created');

      return res.status(201).json({
        success: true,
        data: post,
        message: 'Post created successfully'
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Create post error');
      next(error);
    }
  }

  /**
   * Get a single post by ID
   */
  async getPost(req, res, next) {
    try {
      const { id } = req.params;
      const { uid } = req.user;

      const post = await postRepository.getPostById(id);

      if (!post) {
        return res.status(404).json({
          success: false,
          message: 'Post not found'
        });
      }

      // Get user context for enrichment
      const userContext = await getUserContext(uid);

      // Enrich with user interaction data
      const enrichedPost = {
        ...post,
        isLiked: userContext.likedPostIds.has(post.id),
        isFollowing: userContext.followedUserIds.has(post.authorId)
      };

      return res.json({
        success: true,
        data: enrichedPost
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Get post error');
      next(error);
    }
  }

   /**
    * Get local feed (geographically filtered)
    * 
    * PRODUCTION-GRADE PAGINATION HANDLER:
    * - Input cursor: { createdAt, postId, authorName } JSON string
    * - Output nextCursor: { createdAt, postId, authorName } in pagination object
    * - hasMore: Boolean indicating if more results available
    * - No duplicates: Enforced by deterministic ordering
    */
    async getLocalFeed(req, res, next) {
      try {
        const { uid } = req.user;
        const {
          lat, lng, limit = 20, cursor, mediaType, sid
        } = req.query;

        const pageSize = Math.min(parseInt(limit), 50);

        // Validate coordinates
        geoService.validateCoordinates(parseFloat(lat), parseFloat(lng));

        // Get user context for enrichment
        const userContext = await getUserContext(uid);

        // Collect seen post IDs (from session tracking)
        const seenPostIds = new Set();
        if (sid && req.sessionSeenIds) {
          req.sessionSeenIds.forEach(id => seenPostIds.add(id));
        }

        // Parse composite cursor from JSON string
        // Format: { createdAt: number, postId: string, authorName: string }
        let lastDocSnapshot = null;
        if (cursor) {
          try {
            lastDocSnapshot = JSON.parse(cursor);
            logger.debug(
              { postId: lastDocSnapshot.postId, createdAt: lastDocSnapshot.createdAt },
              '[Controller] Parsed cursor'
            );
          } catch (err) {
            logger.warn({ cursor, error: err }, '[Controller] Invalid cursor format, ignoring');
            // Continue without cursor - start from beginning
          }
        }

        // Calculate geohash bounds from coordinates
        const baseLat = parseFloat(lat);
        const baseLng = parseFloat(lng);
        const precision = 9; // High detail geohash
        const geohash = calculateGeohash(baseLat, baseLng, precision);
        const { min: geoHashMin, max: geoHashMax } = getGeohashBounds(geohash);

        logger.info(
          { lat: baseLat, lng: baseLng, geohash, precision },
          '[Controller] Calculated geohash bounds'
        );

        // Get feed from service
        const feedResult = await feedService.getLocalFeed({
          latitude: baseLat,
          longitude: baseLng,
          seenPostIds,
          pageSize,
          lastDocSnapshot,
          mediaType,
          geoHashMin,
          geoHashMax,
          userContext
        });

        logger.info(
          { uid, lat, lng, postsReturned: feedResult.posts.length, hasMore: feedResult.hasMore },
          '[Controller] Local feed retrieved'
        );

        // Return response with nextCursor for pagination
        return res.json({
          success: true,
          data: feedResult.posts,
          pagination: {
            nextCursor: feedResult.nextCursor,
            hasMore: feedResult.hasMore,
            count: feedResult.posts.length
          }
        });
      } catch (error) {
        logger.error({ error, uid: req.user?.uid }, '[Controller] Get local feed error');
        next(error);
      }
    }

    /**
     * Get global trending feed
     * 
     * PRODUCTION-GRADE PAGINATION HANDLER:
     * - Input cursor: { createdAt, postId, authorName } JSON string
     * - Output nextCursor: { createdAt, postId, authorName } in pagination object
     * - Deterministic ordering: createdAt DESC + __name__ DESC
     * - No duplicates across pages
     */
    async getGlobalFeed(req, res, next) {
      try {
        const { uid } = req.user;
        const { limit = 20, cursor, mediaType } = req.query;

        const pageSize = Math.min(parseInt(limit), 50);

        // Get user context for enrichment
        const userContext = await getUserContext(uid);

        // Collect seen IDs from session
        const seenPostIds = new Set();
        if (req.sessionSeenIds) {
          req.sessionSeenIds.forEach(id => seenPostIds.add(id));
        }

        // Parse composite cursor from JSON string
        let lastDocSnapshot = null;
        if (cursor) {
          try {
            lastDocSnapshot = JSON.parse(cursor);
            logger.debug(
              { postId: lastDocSnapshot.postId, createdAt: lastDocSnapshot.createdAt },
              '[Controller] Parsed cursor'
            );
          } catch (err) {
            logger.warn({ cursor, error: err }, '[Controller] Invalid cursor format, ignoring');
          }
        }

        // Get feed from service
        const feedResult = await feedService.getGlobalFeed({
          seenPostIds,
          pageSize,
          lastDocSnapshot,
          mediaType,
          userContext
        });

        logger.info(
          { uid, postsReturned: feedResult.posts.length, hasMore: feedResult.hasMore },
          '[Controller] Global feed retrieved'
        );

        // Return response with nextCursor for pagination
        return res.json({
          success: true,
          data: feedResult.posts,
          pagination: {
            nextCursor: feedResult.nextCursor,
            hasMore: feedResult.hasMore,
            count: feedResult.posts.length,
            algorithm: 'trending'
          }
        });
      } catch (error) {
        logger.error({ error, uid: req.user?.uid }, '[Controller] Get global feed error');
        next(error);
      }
    }

    /**
     * Get filtered feed (by author, category, city, etc.)
     * 
     * PRODUCTION-GRADE PAGINATION HANDLER:
     * - Input cursor: { createdAt, postId, authorName } JSON string
     * - Output nextCursor: { createdAt, postId, authorName } in pagination object
     * - Deterministic ordering: createdAt DESC + __name__ DESC
     * - No duplicates or jumping
     */
    async getFilteredFeed(req, res, next) {
      try {
        const { uid } = req.user;
        const {
          authorId, category, city, country, limit = 20, cursor, mediaType
        } = req.query;

        const pageSize = Math.min(parseInt(limit), 50);

        // Get user context for enrichment
        const userContext = await getUserContext(uid);

        // Collect seen IDs from session
        const seenPostIds = new Set();
        if (req.sessionSeenIds) {
          req.sessionSeenIds.forEach(id => seenPostIds.add(id));
        }

        // Parse composite cursor from JSON string
         let lastDocSnapshot = null;
         if (cursor) {
           try {
             lastDocSnapshot = JSON.parse(cursor);
             logger.debug(
               { postId: lastDocSnapshot.postId, createdAt: lastDocSnapshot.createdAt },
               '[Controller] Parsed cursor'
             );
           } catch (err) {
             logger.warn({ cursor, error: err }, '[Controller] Invalid cursor format, ignoring');
           }
         }

         // Get feed from service
         const feedResult = await feedService.getFilteredFeed({
           authorId,
           category,
           city,
           country,
           seenPostIds,
           pageSize,
           lastDocSnapshot,
           mediaType,
           userContext
         });

         logger.info(
           { uid, authorId, category, city, country, postsReturned: feedResult.posts.length, hasMore: feedResult.hasMore },
           '[Controller] Filtered feed retrieved'
         );

         // Return response with nextCursor for pagination
         return res.json({
           success: true,
           data: feedResult.posts,
           pagination: {
             nextCursor: feedResult.nextCursor,
             hasMore: feedResult.hasMore,
             count: feedResult.posts.length
           }
         });
       } catch (error) {
         logger.error({ error, uid: req.user?.uid }, '[Controller] Get filtered feed error');
         next(error);
       }
     }

   /**
    * Get hybrid feed (MAIN FEED - local + global merged and deduplicated)
    * 
    * PRODUCTION FEED ENGINE:
    * - Merges local (geographic) + global (broader) content
    * - Hard deduplication prevents duplicates
    * - Returns pagination-safe cursor
    */
    async getHybridFeed(req, res, next) {
      try {
        const { uid } = req.user;
        const {
          lat, lng, limit = 20, cursor, mediaType, sid
        } = req.query;

        const pageSize = Math.min(parseInt(limit), 50);

        // Validate coordinates (required for hybrid)
        geoService.validateCoordinates(parseFloat(lat), parseFloat(lng));

        // Get user context for enrichment
        const userContext = await getUserContext(uid);

        // Collect seen post IDs (from session tracking) for cross-page dedup
        const seenPostIds = new Set();
        if (sid && req.sessionSeenIds) {
          req.sessionSeenIds.forEach(id => seenPostIds.add(id));
        }

        // Parse cursor from JSON string
        let lastDocSnapshot = null;
        if (cursor) {
          try {
            lastDocSnapshot = JSON.parse(cursor);
            logger.debug(
              { postId: lastDocSnapshot.postId, createdAt: lastDocSnapshot.createdAt },
              '[Controller] Parsed hybrid cursor'
            );
          } catch (err) {
            logger.warn({ cursor, error: err }, '[Controller] Invalid hybrid cursor format, ignoring');
          }
        }

        // Calculate geohash bounds from coordinates
        const baseLat = parseFloat(lat);
        const baseLng = parseFloat(lng);
        const precision = 9;
        const geohash = calculateGeohash(baseLat, baseLng, precision);
        const { min: geoHashMin, max: geoHashMax } = getGeohashBounds(geohash);

        logger.info(
          { uid, lat: baseLat, lng: baseLng, geohash, precision },
          '[Controller] Calculated geohash for hybrid feed'
        );

        // Get hybrid feed from service (MAIN FEED ENGINE)
        const feedResult = await feedService.getHybridFeed({
          latitude: baseLat,
          longitude: baseLng,
          geoHashMin,
          geoHashMax,
          seenPostIds,
          pageSize,
          lastDocSnapshot,
          mediaType,
          userContext
        });

        logger.info(
          {
            uid,
            lat: baseLat,
            lng: baseLng,
            postsReturned: feedResult.posts.length,
            hasMore: feedResult.hasMore,
            mergeInfo: feedResult.pagination?.mergeInfo
          },
          '[Controller] Hybrid feed retrieved'
        );

        // Return response with nextCursor for pagination
        return res.json({
          success: true,
          data: feedResult.posts,
          pagination: {
            nextCursor: feedResult.nextCursor,
            hasMore: feedResult.hasMore,
            count: feedResult.posts.length,
            mergeInfo: feedResult.pagination?.mergeInfo
          }
        });
      } catch (error) {
        logger.error({ error, uid: req.user?.uid }, '[Controller] Get hybrid feed error');
        next(error);
      }
    }

   /**
    * Update a post
    */
  async updatePost(req, res, next) {
    try {
      const { id } = req.params;
      const { uid } = req.user;
      const updates = req.body;

      // Verify ownership
      const post = await postRepository.getPostById(id);
      if (!post || post.authorId !== uid) {
        return res.status(403).json({
          success: false,
          message: 'Unauthorized to update this post'
        });
      }

      // Update
      const updated = await postRepository.updatePost(id, updates);

      logger.info({ postId: id, uid }, '[Controller] Post updated');

      return res.json({
        success: true,
        data: updated,
        message: 'Post updated successfully'
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Update post error');
      next(error);
    }
  }

  /**
   * Delete a post
   */
  async deletePost(req, res, next) {
    try {
      const { id } = req.params;
      const { uid } = req.user;

      // Verify ownership
      const post = await postRepository.getPostById(id);
      if (!post || post.authorId !== uid) {
        return res.status(403).json({
          success: false,
          message: 'Unauthorized to delete this post'
        });
      }

      // Delete
      await postRepository.deletePost(id);

      logger.info({ postId: id, uid }, '[Controller] Post deleted');

      return res.json({
        success: true,
        message: 'Post deleted successfully'
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Delete post error');
      next(error);
    }
  }

  /**
   * Increment view count for a post
   */
  async viewPost(req, res, next) {
    try {
      const { id } = req.params;
      const { uid } = req.user;

      await postRepository.updatePost(id, {
        viewCount: admin.firestore.FieldValue.increment(1)
      });

      logger.info({ postId: id, uid }, '[Controller] Post viewed');

      return res.json({
        success: true,
        message: 'View recorded'
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] View post error');
      next(error);
    }
  }
}

export default new PostController();
