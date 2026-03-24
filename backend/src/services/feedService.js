/**
 * Feed Service - Business logic for feed generation
 * 
 * Coordinates between:
 * - PostRepository (data access)
 * - UserContext (user preferences, likes, follows)
 * - Trending algorithms
 * - Deduplication logic
 */

import postRepository from '../repositories/postRepository.js';
import logger from '../utils/logger.js';

// Constants
const TRENDING_WINDOW_MS = 72 * 60 * 60 * 1000; // 72 hours
const ENGAGEMENT_DECAY = 0.95; // Per hour decay factor
const BASE_TRENDING_SCORE = 100;

class FeedService {
  /**
   * Calculate time-decay trending score
   * Newer posts + higher engagement = higher score
   */
  calculateTrendingScore(post) {
    if (!post.createdAt) return 0;

    const postAge = Date.now() - post.createdAt.toMillis();
    const hoursOld = postAge / (60 * 60 * 1000);

    // Decay: score drops by 5% per hour
    const decayMultiplier = Math.pow(ENGAGEMENT_DECAY, hoursOld);

    // Base engagement: likes + comments*2 + views*0.1
    const engagementBase = (post.likeCount || 0) + 
                          ((post.commentCount || 0) * 2) + 
                          ((post.viewCount || 0) * 0.1);

    return (BASE_TRENDING_SCORE + engagementBase) * decayMultiplier;
  }

  /**
   * Get local feed with proper filtering and curation
   */
  async getLocalFeed({
    latitude,
    longitude,
    seenPostIds = new Set(),
    pageSize = 20,
    lastDocSnapshot = null,
    mediaType = null,
    geoHashMin,
    geoHashMax,
    userContext = null // {likedPostIds, followedUserIds, mutedUserIds}
  }) {
    try {
      // Fetch from repository
      const result = await postRepository.getLocalFeed({
        geoHashMin,
        geoHashMax,
        seenPostIds,
        pageSize,
        lastDocSnapshot,
        mediaType
      });

      // Apply user preferences (muting, etc.)
      let posts = result.posts;
      if (userContext && userContext.mutedUserIds) {
        posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
      }

      // Enrich with user interaction data
      if (userContext) {
        posts = posts.map(post => ({
          ...post,
          isLiked: userContext.likedPostIds?.has(post.id) || false,
          isFollowing: userContext.followedUserIds?.has(post.authorId) || false
        }));
      }

      return {
        posts,
        cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
        hasMore: result.hasMore,
        pagination: {
          cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
          hasMore: result.hasMore
        }
      };
    } catch (error) {
      logger.error({
        latitude, longitude, error
      }, '[FeedService] Error getting local feed');
      throw error;
    }
  }

  /**
   * Get global trending feed
   */
  async getGlobalFeed({
    seenPostIds = new Set(),
    pageSize = 20,
    lastDocSnapshot = null,
    mediaType = null,
    userContext = null
  }) {
    try {
      // Calculate time window for trending (last 72 hours)
      const cutoffTime = new Date(Date.now() - TRENDING_WINDOW_MS);

      // Fetch posts from last 72 hours
      const result = await postRepository.getGlobalFeed({
        seenPostIds,
        pageSize: pageSize * 2, // Fetch more since we'll sort by trending
        lastDocSnapshot,
        mediaType,
        afterDate: cutoffTime
      });

      // Calculate trending scores and sort
      const postsWithScores = result.posts.map(post => ({
        ...post,
        trendingScore: this.calculateTrendingScore(post)
      }));

      postsWithScores.sort((a, b) => b.trendingScore - a.trendingScore);

      // Take top posts
      const trendingPosts = postsWithScores.slice(0, pageSize);

      // Apply user preferences
      let posts = trendingPosts;
      if (userContext && userContext.mutedUserIds) {
        posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
      }

      // Enrich with user interaction data
      if (userContext) {
        posts = posts.map(post => ({
          ...post,
          isLiked: userContext.likedPostIds?.has(post.id) || false,
          isFollowing: userContext.followedUserIds?.has(post.authorId) || false
        }));
      }

      return {
        posts,
        cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
        hasMore: posts.length >= pageSize,
        pagination: {
          cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
          hasMore: posts.length >= pageSize,
          algorithm: 'trending'
        }
      };
    } catch (error) {
      logger.error({
        error
      }, '[FeedService] Error getting global feed');
      throw error;
    }
  }

  /**
   * Get filtered feed (author, category, city, etc.)
   */
  async getFilteredFeed({
    authorId = null,
    category = null,
    city = null,
    country = null,
    seenPostIds = new Set(),
    pageSize = 20,
    lastDocSnapshot = null,
    mediaType = null,
    userContext = null
  }) {
    try {
      const result = await postRepository.getFilteredFeed({
        authorId,
        category,
        city,
        country,
        seenPostIds,
        pageSize,
        lastDocSnapshot,
        mediaType
      });

      // Apply user preferences
      let posts = result.posts;
      if (userContext && userContext.mutedUserIds) {
        posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
      }

      // Enrich with user interaction data
      if (userContext) {
        posts = posts.map(post => ({
          ...post,
          isLiked: userContext.likedPostIds?.has(post.id) || false,
          isFollowing: userContext.followedUserIds?.has(post.authorId) || false
        }));
      }

      return {
        posts,
        cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
        hasMore: result.hasMore,
        pagination: {
          cursor: posts.length > 0 ? posts[posts.length - 1].id : null,
          hasMore: result.hasMore
        }
      };
    } catch (error) {
      logger.error({
        authorId, category, city, country, error
      }, '[FeedService] Error getting filtered feed');
      throw error;
    }
  }
}

export default new FeedService();
