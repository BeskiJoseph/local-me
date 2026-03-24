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
   * Compute ranking score for a post
   * 
   * PHASE 4: Lightweight heuristic ranking
   * Applied ONLY to merged batch (not DB-wide)
   * 
   * Weights:
   * - Recency (0.5): Newer posts prioritized
   * - Engagement (0.3): Likes + comments + views
   * - Distance (0.2): Geographic proximity (if available)
   * 
   * @param {Object} post - Post object
   * @param {Object} userLocation - {latitude, longitude} for distance calc
   * @returns {number} - Score (higher = better)
   */
  computeScore(post, userLocation = null) {
    if (!post.createdAt) return 0;

    const now = Date.now();
    
    // 1. RECENCY SCORE (0.5 weight)
    // Newer posts = higher score
    // Formula: 1 / (1 + hoursOld) → decays smoothly
    const postCreatedMs = post.createdAt.toMillis?.() || post.createdAt;
    const hoursOld = (now - postCreatedMs) / (1000 * 60 * 60);
    const recencyScore = 1 / (1 + hoursOld);

    // 2. ENGAGEMENT SCORE (0.3 weight)
    // Likes + Comments*2 + Views*0.1
    const engagement =
      (post.likeCount || 0) +
      (post.commentCount || 0) * 2 +
      (post.viewCount || 0) * 0.1;
    
    // Normalize engagement to 0-1 range (max 100 engagement = score 1)
    const engagementScore = Math.min(engagement / 100, 1);

    // 3. DISTANCE SCORE (0.2 weight)
    // Geographic proximity if available
    // Formula: 1 / (1 + distanceKm)
    let distanceScore = 0;
    if (userLocation && post.latitude && post.longitude) {
      const distance = this.calculateDistance(
        userLocation.latitude,
        userLocation.longitude,
        post.latitude,
        post.longitude
      );
      // Closer = higher score
      distanceScore = 1 / (1 + distance);
    }

    // FINAL SCORE (weighted sum)
    const finalScore =
      recencyScore * 0.5 +
      engagementScore * 0.3 +
      distanceScore * 0.2;

    return finalScore;
  }

  /**
   * Calculate distance between two geographic points (Haversine formula)
   * @param {number} lat1 - User latitude
   * @param {number} lng1 - User longitude
   * @param {number} lat2 - Post latitude
   * @param {number} lng2 - Post longitude
   * @returns {number} - Distance in kilometers
   */
  calculateDistance(lat1, lng1, lat2, lng2) {
    const R = 6371; // Earth's radius in km
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

   /**
    * Get local feed with proper filtering and curation
    */
    async getLocalFeed({
      latitude,
      longitude,
      pageSize = 20,
      lastDocSnapshot = null,
      mediaType = null,
      geoHashMin,
      geoHashMax,
      userContext = null
    }) {
     try {
       // Fetch from repository
        const result = await postRepository.getLocalFeed({
          geoHashMin,
          geoHashMax,
          pageSize,
          lastDocSnapshot,
          mediaType
        });
        // Apply user preferences (muting, etc.)
        let posts = result.posts;
        if (userContext && userContext.mutedUserIds) {
          posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
        }

        // 1. CALCULATE DISTANCE AND SCORE
        const userLocation = { latitude, longitude };
        posts = posts.map(post => {
          let distance = 999999;
          if (post.latitude && post.longitude) {
            distance = this.calculateDistance(
              latitude,
              longitude,
              post.latitude,
              post.longitude
            );
          }
          return {
            ...post,
            distance,
            score: this.computeScore(post, userLocation)
          };
        });

        // 2. EXPLICIT SORT: Distance (ASC) then createdAt (DESC)
        posts.sort((a, b) => {
          if (Math.abs(a.distance - b.distance) > 0.1) { // 100m tolerance for stable buckets
            return a.distance - b.distance;
          }
          const timeA = a.createdAt?.toMillis?.() || a.createdAt || 0;
          const timeB = b.createdAt?.toMillis?.() || b.createdAt || 0;
          return timeB - timeA;
        });

        // Enrich with user interaction data
        if (userContext) {
          posts = posts.map(post => ({
            ...post,
            isLiked: userContext.likedPostIds?.has(post.id) || false,
            isFollowing: userContext.followedUserIds?.has(post.authorId) || false
          }));
        }

        // Build composite cursor from last post (createdAt + postId for determinism)
        const lastPost = posts.length > 0 ? posts[posts.length - 1] : null;
        const nextCursor = lastPost ? {
          createdAt: lastPost.createdAt ? lastPost.createdAt.toMillis?.() || lastPost.createdAt : Date.now(),
          postId: lastPost.id,
          authorName: lastPost.authorName || ''
        } : null;

        return {
          posts,
          nextCursor,
          hasMore: result.hasMore,
          pagination: {
            nextCursor,
            hasMore: result.hasMore,
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
    * Get global feed (createdAt ordering, NOT trending sort)
    * 
    * CRITICAL: Do NOT sort by trending after pagination.
    * Trending will be handled in Phase 4 (DB-level or precomputed).
    * For now: Keep createdAt DESC ordering for consistency.
    */
    async getGlobalFeed({
      pageSize = 20,
      lastDocSnapshot = null,
      mediaType = null,
      userContext = null
    }) {
     try {
       // Calculate time window (last 72 hours)
       const cutoffTime = new Date(Date.now() - TRENDING_WINDOW_MS);

        // Fetch posts from last 72 hours, already sorted by createdAt DESC + __name__ DESC
        const result = await postRepository.getGlobalFeed({
          pageSize,
          lastDocSnapshot,
          mediaType,
          afterDate: cutoffTime
        });

        // Apply user preferences (muting)
        let posts = result.posts;
        if (userContext && userContext.mutedUserIds) {
          posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
        }

        // 1. CALCULATE TRENDING SCORES
        // Score = ((likes * 2) + (comments * 3)) * timeDecay
        posts = posts.map(post => ({
          ...post,
          score: this.calculateTrendingScore(post)
        }));

        // 2. EXPLICIT SORT: Score (DESC)
        posts.sort((a, b) => b.score - a.score);

        // Enrich with user interaction data
        if (userContext) {
          posts = posts.map(post => ({
            ...post,
            isLiked: userContext.likedPostIds?.has(post.id) || false,
            isFollowing: userContext.followedUserIds?.has(post.authorId) || false
          }));
        }

        // Build composite cursor from last post
        const lastPost = posts.length > 0 ? posts[posts.length - 1] : null;
        const nextCursor = lastPost ? {
          createdAt: lastPost.createdAt ? lastPost.createdAt.toMillis?.() || lastPost.createdAt : Date.now(),
          postId: lastPost.id,
          authorName: lastPost.authorName || ''
        } : null;

        return {
          posts,
          nextCursor,
          hasMore: result.hasMore,
          pagination: {
            nextCursor,
            hasMore: result.hasMore
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

        // Build composite cursor from last post (createdAt + postId + authorName for determinism)
        const lastPost = posts.length > 0 ? posts[posts.length - 1] : null;
        const nextCursor = lastPost ? {
          createdAt: lastPost.createdAt ? lastPost.createdAt.toMillis?.() || lastPost.createdAt : Date.now(),
          postId: lastPost.id,
          authorName: lastPost.authorName || ''
        } : null;

        return {
          posts,
          nextCursor,
          hasMore: result.hasMore,
          pagination: {
            nextCursor,
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

   /**
    * Deduplicate posts by ID
    * 
    * CRITICAL: This is the HARD dedup layer that prevents duplicates
    * across multiple feed sources (local + global merge).
    * 
    * @param {Array} posts - Posts to deduplicate
    * @param {Set} seenIds - Existing seen IDs (cross-page dedup)
    * @returns {Array} - Deduplicated posts
    */
   deduplicatePosts(posts, seenIds = new Set()) {
     const seen = new Set(seenIds);
     const result = [];

     for (const post of posts) {
       if (seen.has(post.id)) {
         logger.debug({ postId: post.id }, '[FeedService] Skipping duplicate post');
         continue;
       }
       seen.add(post.id);
       result.push(post);
     }

     logger.info(
       { totalInput: posts.length, deduped: result.length, skipped: posts.length - result.length },
       '[FeedService] Deduplication complete'
     );

     return result;
   }

   /**
    * Get hybrid feed (MERGE + DEDUP + CURSOR)
    * 
    * PIPELINE:
    * 1. Fetch local feed (user's geographic area)
    * 2. Fetch global feed (broader content)
    * 3. Merge: [local posts, global posts] (local has priority)
    * 4. Deduplicate: Remove any post appearing in both
    * 5. Limit: Take pageSize posts AFTER dedup
    * 6. Build cursor: From final merged posts
    * 7. Return: With strong seenIds for cross-page dedup
    * 
    * This is the MAIN FEED ENGINE.
    */
    async getHybridFeed({
      latitude,
      longitude,
      geoHashMin,
      geoHashMax,
      pageSize = 20,
      lastDocSnapshot = null,
      mediaType = null,
      userContext = null
    }) {
      try {
        logger.info(
          { lat: latitude, lng: longitude, pageSize },
          '[FeedService] Starting hybrid feed interleaving'
        );

        // STEP 1: Fetch sources separately
        // We fetch enough to satisfy the interleave pattern roughly
        const localCount = Math.ceil(pageSize * 0.75) + 5;
        const globalCount = Math.ceil(pageSize * 0.25) + 5;

        const [localResult, globalResult] = await Promise.all([
          this.getLocalFeed({
            latitude, longitude, geoHashMin, geoHashMax,
            pageSize: localCount, lastDocSnapshot, mediaType, userContext
          }),
          this.getGlobalFeed({
            pageSize: globalCount, lastDocSnapshot, mediaType, userContext
          })
        ]);

        // STEP 2: Interleave pattern [L, L, L, G]
        const finalPosts = [];
        const localQueue = [...localResult.posts];
        const globalQueue = [...globalResult.posts];

        while (finalPosts.length < pageSize && (localQueue.length > 0 || globalQueue.length > 0)) {
          // Add up to 3 local posts
          for (let i = 0; i < 3 && localQueue.length > 0 && finalPosts.length < pageSize; i++) {
            finalPosts.push(localQueue.shift());
          }
          // Add 1 global post
          if (globalQueue.length > 0 && finalPosts.length < pageSize) {
            finalPosts.push(globalQueue.shift());
          }
        }

        // STEP 3: Deterministic Cursor from the absolute last post
        const lastPost = finalPosts.length > 0 ? finalPosts[finalPosts.length - 1] : null;
        const nextCursor = lastPost ? {
          createdAt: lastPost.createdAt ? lastPost.createdAt.toMillis?.() || lastPost.createdAt : Date.now(),
          postId: lastPost.id
        } : null;

        return {
          posts: finalPosts,
          nextCursor,
          hasMore: localResult.hasMore || globalResult.hasMore,
          pagination: {
            nextCursor,
            hasMore: localResult.hasMore || globalResult.hasMore
          }
        };
      } catch (error) {
       logger.error(
         { latitude, longitude, error },
         '[FeedService] Error getting hybrid feed'
       );
       throw error;
     }
   }

   /**
    * Get explore grid content (MIXED RATIO)
    * 
    * RATIO: 
    * - 40% Trending (Global)
    * - 30% Nearby (Local)
    * - 30% New/Random (Global without score)
    */
   async getExploreGrid({
     latitude,
     longitude,
     geoHashMin,
     geoHashMax,
     pageSize = 30,
     userContext = null
   }) {
     try {
       const countTrending = Math.ceil(pageSize * 0.4);
       const countNearby = Math.ceil(pageSize * 0.3);
       const countRandom = pageSize - countTrending - countNearby;

       // Fetch sources in parallel
       const [trending, nearby, recent] = await Promise.all([
         this.getGlobalFeed({ pageSize: countTrending, userContext }),
         (latitude && longitude && geoHashMin && geoHashMax) 
           ? this.getLocalFeed({ latitude, longitude, geoHashMin, geoHashMax, pageSize: countNearby, userContext })
           : { posts: [] },
         this.getGlobalFeed({ pageSize: countRandom * 2, userContext }) // Fetch more for variety
       ]);

       // Merge and shuffle slightly for that "explore" feel
       let mixed = [
         ...trending.posts,
         ...nearby.posts,
         ...recent.posts.slice(0, countRandom)
       ];

       // Deduplicate
       mixed = this.deduplicatePosts(mixed);

       // Sort: Mix them up but keep trending somewhat high
       mixed.sort((a, b) => (b.score || 0) * (0.8 + Math.random() * 0.4) - (a.score || 0) * (0.8 + Math.random() * 0.4));

       return {
         posts: mixed.slice(0, pageSize),
         hasMore: trending.hasMore || nearby.hasMore || recent.hasMore
       };
     } catch (error) {
       logger.error({ error }, '[FeedService] Error getting explore grid');
       throw error;
     }
   }
}

export default new FeedService();
;
