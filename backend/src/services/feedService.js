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
const TRENDING_WINDOW_MS = 30 * 24 * 60 * 60 * 1000; // Relaxed to 30 days for dev stability
const ENGAGEMENT_DECAY = 0.95; // Per hour decay factor
const BASE_TRENDING_SCORE = 100;

class FeedService {
  /**
   * Normalize various timestamp formats to milliseconds
   */
  normalizeTimestamp(ts) {
    if (!ts) return 0;
    if (typeof ts === 'object' && ts._seconds !== undefined) {
      return ts._seconds * 1000 + (ts._nanoseconds || 0) / 1000000;
    }
    if (ts.toMillis && typeof ts.toMillis === 'function') {
      return ts.toMillis();
    }
    const date = new Date(ts);
    return isNaN(date.getTime()) ? 0 : date.getTime();
  }

  calculateTrendingScore(post) {
    const createdAtMs = this.normalizeTimestamp(post.createdAt);
    if (!createdAtMs) return 0;

    const postAge = Date.now() - createdAtMs;
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
    const postCreatedMs = this.normalizeTimestamp(post.createdAt);
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
        // Fetch from repository (uses real pageSize from controller, no override)
        console.log(`[FeedService] 🔍 lastDocSnapshot received:`, lastDocSnapshot ? JSON.stringify(lastDocSnapshot) : 'NULL');
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

        // 1. PRE-CALCULATE DISTANCE AND SCORE
        const userLat = parseFloat(latitude);
        const userLng = parseFloat(longitude);
        const hasUserLocation = !isNaN(userLat) && !isNaN(userLng);

        posts = posts.map(post => {
          let distance = Infinity;
          
          if (hasUserLocation) {
            const lat = post.latitude ?? post.location?.lat;
            const lng = post.longitude ?? post.location?.lng;

            if (lat != null && lng != null) {
              distance = this.calculateDistance(userLat, userLng, lat, lng);
            }
          }
          
          return {
            ...post,
            normalizedCreatedAt: this.normalizeTimestamp(post.createdAt),
            distance,
            score: this.computeScore(post, { latitude: userLat, longitude: userLng })
          };
        });

        // 2. SORT: Distance (ASC) with 100m tolerance, then createdAt (DESC)
        const DISTANCE_TOLERANCE = 0.1; // 100 meters
        const sortedPosts = [...posts].sort((a, b) => {
          const distDiff = a.distance - b.distance;
          
          // If distance difference is more than tolerance, use distance
          if (Math.abs(distDiff) > DISTANCE_TOLERANCE) {
            return distDiff;
          }
          
          // Otherwise, sort by recency
          return b.normalizedCreatedAt - a.normalizedCreatedAt;
        });

        posts = sortedPosts;

        // Enrich with user interaction data
        if (userContext) {
          posts = posts.map(post => ({
            ...post,
            isLiked: userContext.likedPostIds?.has(post.id) || false,
            isFollowing: userContext.followedUserIds?.has(post.authorId) || false
          }));
        }
        // 3. 🔥 CRITICAL: Cursor from REPOSITORY's last Firestore doc
        // NOT from distance-sorted last post (which would point to wrong Firestore position)
        const repoLastDoc = result.lastDoc;
        let nextCursor = null;
        if (repoLastDoc) {
          if (typeof repoLastDoc.data === 'function') {
            // Real Firestore DocumentSnapshot
            const data = repoLastDoc.data();
            nextCursor = {
              createdAt: this.normalizeTimestamp(data.createdAt),
              id: repoLastDoc.id,
            };
          } else {
            // POJO from mapDocToPost
            nextCursor = {
              createdAt: this.normalizeTimestamp(repoLastDoc.createdAt),
              id: repoLastDoc.id,
            };
          }
        }
        console.log(`[FeedService] 📌 NextCursor: createdAt=${nextCursor?.createdAt}, id=${nextCursor?.id}`);

        logger.info(
          { count: posts.length, hasMore: result.hasMore },
          '[FeedService] Local feed page returned'
        );

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
        posts = result.posts.map(post => ({
          ...post,
          normalizedCreatedAt: this.normalizeTimestamp(post.createdAt),
          score: this.calculateTrendingScore(post)
        }));

        // 2. EXPLICIT IMMUTABLE SORT: Score (DESC) then createdAt (DESC)
        const sortedPosts = [...posts].sort((a, b) => {
          if (b.score !== a.score) {
            return b.score - a.score;
          }
          return b.normalizedCreatedAt - a.normalizedCreatedAt;
        });

        posts = sortedPosts;

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
          createdAt: lastPost.normalizedCreatedAt || this.normalizeTimestamp(lastPost.createdAt),
          id: lastPost.id,
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
          createdAt: lastPost.normalizedCreatedAt || this.normalizeTimestamp(lastPost.createdAt),
          id: lastPost.id,
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
      dualCursor = null,  // Changed parameter name
      mediaType = null,
      userContext = null
    }) {
      try {
         // Extract individual cursors from dual cursor
         const localCursor = dualCursor?.localCursor || null;
         const globalCursor = dualCursor?.globalCursor || null;
         
         // STEP 1: Fetch sources with OVERHEAD for dedup
         const fetchLimit = pageSize * 2;
         const localCount = Math.ceil(fetchLimit * 0.75);
         const globalCount = Math.ceil(fetchLimit * 0.25) + pageSize; // Large buffer for global

         const [localResult, globalResult] = await Promise.all([
           this.getLocalFeed({
             latitude, longitude, geoHashMin, geoHashMax,
             pageSize: localCount, lastDocSnapshot: localCursor, mediaType, userContext
           }),
           this.getGlobalFeed({
             pageSize: globalCount, lastDocSnapshot: globalCursor, mediaType, userContext
           })
         ]);

         // STEP 2: CRITICAL FIX - Filter global to exclude local IDs before interleaving
         // Build set of local post IDs
         const localIds = new Set(localResult.posts.map(p => p.id));
         const filteredGlobalPosts = globalResult.posts.filter(p => !localIds.has(p.id));
         
         logger.info({
           localCount: localResult.posts.length,
           globalCountRaw: globalResult.posts.length,
           globalCountFiltered: filteredGlobalPosts.length,
           duplicatesRemoved: globalResult.posts.length - filteredGlobalPosts.length
         }, '[FeedService] Filtered global posts to exclude local');

          // STEP 3: Interleave [3L, 1G] with post-merge DEDUP + STREAM TRACKING
          const seenIds = new Set();
          const finalPosts = [];
          const postSources = new Map(); // Track which stream each final post came from
          const localQueue = [...localResult.posts];
          const globalQueue = [...filteredGlobalPosts];

          logger.info({
            localIds: localQueue.map(p => p.id),
            globalIds: globalQueue.map(p => p.id),
            totalLocalQueue: localQueue.length,
            totalGlobalQueue: globalQueue.length
          }, '[FeedService] Starting interleaving merge (after duplicate exclusion)');

         let li = 0, gi = 0;
         while (finalPosts.length < pageSize && (li < localQueue.length || gi < globalQueue.length)) {
           // Add up to 3 unique local posts (PRIORITY)
           for (let i = 0; i < 3 && li < localQueue.length && finalPosts.length < pageSize; i++) {
             const post = localQueue[li++];
             if (!seenIds.has(post.id)) {
               seenIds.add(post.id);
               finalPosts.push(post);
               postSources.set(post.id, { stream: 'local', queueIndex: li - 1 });
             }
           }
           
           // Add 1 unique global post (FALLBACK)
           if (gi < globalQueue.length && finalPosts.length < pageSize) {
             const post = globalQueue[gi++];
             if (!seenIds.has(post.id)) {
               seenIds.add(post.id);
               finalPosts.push(post);
               postSources.set(post.id, { stream: 'global', queueIndex: gi - 1 });
             }
           }
         }

         // STEP 3: Fallback - if still under pageSize, drain as much as possible
         while (finalPosts.length < pageSize && (li < localQueue.length || gi < globalQueue.length)) {
           if (li < localQueue.length) {
             const post = localQueue[li++];
             if (!seenIds.has(post.id)) {
               seenIds.add(post.id);
               finalPosts.push(post);
               postSources.set(post.id, { stream: 'local', queueIndex: li - 1 });
             }
           } else if (gi < globalQueue.length) {
             const post = globalQueue[gi++];
             if (!seenIds.has(post.id)) {
               seenIds.add(post.id);
               finalPosts.push(post);
               postSources.set(post.id, { stream: 'global', queueIndex: gi - 1 });
             }
           }
         }

          logger.info({
            finalIds: finalPosts.map(p => p.id),
            count: finalPosts.length,
            localConsumed: li,
            globalConsumed: gi,
            localQueueSize: localQueue.length,
            globalQueueSize: globalQueue.length,
            streamBreakdown: {
              localPostsInFinal: finalPosts.filter((p, i) => postSources.get(p.id)?.stream === 'local').length,
              globalPostsInFinal: finalPosts.filter((p, i) => postSources.get(p.id)?.stream === 'global').length
            }
          }, '[FeedService] Interleaving merge complete');

          // STEP 4: Build DUAL cursor ONLY from posts that actually appear in finalPosts
          // CRITICAL FIX: Don't use queue indices (li, gi) - those don't map to final posts!
          // Instead, find the LAST post from each stream that actually appears in finalPosts
          
          // Find last local post in final posts
          let lastLocalPost = null;
          for (let i = finalPosts.length - 1; i >= 0; i--) {
            const source = postSources.get(finalPosts[i].id);
            if (source?.stream === 'local') {
              lastLocalPost = finalPosts[i];
              break;
            }
          }
          
          // Find last global post in final posts
          let lastGlobalPost = null;
          for (let i = finalPosts.length - 1; i >= 0; i--) {
            const source = postSources.get(finalPosts[i].id);
            if (source?.stream === 'global') {
              lastGlobalPost = finalPosts[i];
              break;
            }
          }
          
          const nextCursor = {
            // Local stream cursor (for distance-sorted feed)
            localCursor: lastLocalPost ? {
              createdAt: lastLocalPost.normalizedCreatedAt || this.normalizeTimestamp(lastLocalPost.createdAt),
              id: lastLocalPost.id,
              distance: lastLocalPost.distance // Include distance for local stream
            } : null,
            
            // Global stream cursor (for trending-sorted feed)
            globalCursor: lastGlobalPost ? {
              createdAt: lastGlobalPost.normalizedCreatedAt || this.normalizeTimestamp(lastGlobalPost.createdAt),
              id: lastGlobalPost.id,
              score: lastGlobalPost.score // Include trending score for global stream
            } : null
          };

          logger.info({
            nextCursor,
            lastLocalId: lastLocalPost?.id,
            lastGlobalId: lastGlobalPost?.id,
            cursorBuildMethod: 'FROM_FINAL_POSTS_ONLY',
            previousQueueMethod: `li=${li}, gi=${gi} (NOT USED - source of bug!)`
          }, '[FeedService] Built dual cursor for next page (FIXED: using finalPosts, not queue indices)');

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
