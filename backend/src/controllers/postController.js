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
   */
  async getLocalFeed(req, res, next) {
    try {
      const { uid } = req.user;
      const {
        lat, lng, limit = 20, afterId, mediaType, sid
      } = req.query;

      const pageSize = Math.min(parseInt(limit), 50);

      // Validate coordinates
      geoService.validateCoordinates(parseFloat(lat), parseFloat(lng));

      // Get user context
      const userContext = await getUserContext(uid);

      // Collect seen post IDs (from session and watchedIds)
      const seenPostIds = new Set();
      
      // Session tracking (if provided)
      if (sid && req.sessionSeenIds) {
        req.sessionSeenIds.forEach(id => seenPostIds.add(id));
      }

      // Get the current scroll distance for geohash precision
      let lastDoc = null;
      if (afterId) {
        lastDoc = await postRepository.getPostById(afterId);
      }

      // Calculate geohash bounds from coordinates
      const baseLat = parseFloat(lat);
      const baseLng = parseFloat(lng);
      
      // Start with precision 9 (high detail)
      const precision = 9;
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
        lastDocSnapshot: lastDoc ? { id: lastDoc.id } : null,
        mediaType,
        geoHashMin,
        geoHashMax,
        userContext
      });

      logger.info(
        { uid, lat, lng, postsReturned: feedResult.posts.length },
        '[Controller] Local feed retrieved'
      );

      return res.json({
        success: true,
        data: feedResult.posts,
        pagination: feedResult.pagination
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Get local feed error');
      next(error);
    }
  }

  /**
   * Get global trending feed
   */
  async getGlobalFeed(req, res, next) {
    try {
      const { uid } = req.user;
      const { limit = 20, afterId, mediaType } = req.query;

      const pageSize = Math.min(parseInt(limit), 50);

      // Get user context
      const userContext = await getUserContext(uid);

      // Collect seen IDs
      const seenPostIds = new Set();
      if (req.sessionSeenIds) {
        req.sessionSeenIds.forEach(id => seenPostIds.add(id));
      }

      // Get last document for cursor pagination
      let lastDoc = null;
      if (afterId) {
        lastDoc = await postRepository.getPostById(afterId);
      }

      // Get feed from service
      const feedResult = await feedService.getGlobalFeed({
        seenPostIds,
        pageSize,
        lastDocSnapshot: lastDoc ? { id: lastDoc.id } : null,
        mediaType,
        userContext
      });

      logger.info(
        { uid, postsReturned: feedResult.posts.length },
        '[Controller] Global feed retrieved'
      );

      return res.json({
        success: true,
        data: feedResult.posts,
        pagination: feedResult.pagination
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Get global feed error');
      next(error);
    }
  }

  /**
   * Get filtered feed (by author, category, city, etc.)
   */
  async getFilteredFeed(req, res, next) {
    try {
      const { uid } = req.user;
      const {
        authorId, category, city, country, limit = 20, afterId, mediaType
      } = req.query;

      const pageSize = Math.min(parseInt(limit), 50);

      // Get user context
      const userContext = await getUserContext(uid);

      // Collect seen IDs
      const seenPostIds = new Set();
      if (req.sessionSeenIds) {
        req.sessionSeenIds.forEach(id => seenPostIds.add(id));
      }

      // Get last document for cursor pagination
      let lastDoc = null;
      if (afterId) {
        lastDoc = await postRepository.getPostById(afterId);
      }

      // Get feed from service
      const feedResult = await feedService.getFilteredFeed({
        authorId,
        category,
        city,
        country,
        seenPostIds,
        pageSize,
        lastDocSnapshot: lastDoc ? { id: lastDoc.id } : null,
        mediaType,
        userContext
      });

      logger.info(
        { uid, authorId, category, city, postsReturned: feedResult.posts.length },
        '[Controller] Filtered feed retrieved'
      );

      return res.json({
        success: true,
        data: feedResult.posts,
        pagination: feedResult.pagination
      });
    } catch (error) {
      logger.error({ error, uid: req.user?.uid }, '[Controller] Get filtered feed error');
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
