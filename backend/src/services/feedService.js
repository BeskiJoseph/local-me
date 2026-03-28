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
        
        // 🔥 MAX RADIUS for local feed: 50km
        const MAX_LOCAL_RADIUS_KM = 50.0;

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
        
        // 🔥 FILTER: Only include posts within max radius (50km)
        const beforeFilter = posts.length;
        posts = posts.filter(post => post.distance <= MAX_LOCAL_RADIUS_KM);
        const excluded = beforeFilter - posts.length;
        if (excluded > 0) {
          logger.info({ excluded, maxRadius: MAX_LOCAL_RADIUS_KM }, '[FeedService] Excluded posts beyond max radius');
        }

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
              postId: repoLastDoc.id,
            };
          } else {
            // POJO from mapDocToPost
            nextCursor = {
              createdAt: this.normalizeTimestamp(repoLastDoc.createdAt),
              id: repoLastDoc.id,
              postId: repoLastDoc.id,
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
        posts = posts.map(post => ({
          ...post,
          normalizedCreatedAt: this.normalizeTimestamp(post.createdAt),
          score: this.calculateTrendingScore(post)
        }));

        // Keep repository ordering stable for cursor continuity.
        // The UI can still use score for display hints without reordering pages.

        // Enrich with user interaction data
        if (userContext) {
          posts = posts.map(post => ({
            ...post,
            isLiked: userContext.likedPostIds?.has(post.id) || false,
            isFollowing: userContext.followedUserIds?.has(post.authorId) || false
          }));
        }

        // Build pagination cursor from repository order, not post-score order.
        // This keeps cursor movement stable even when UI ranking reorders the page.
        const repoLastDoc = result.lastDoc;
        let nextCursor = null;
        if (repoLastDoc) {
          if (typeof repoLastDoc.data === 'function') {
            const data = repoLastDoc.data();
            nextCursor = {
              createdAt: this.normalizeTimestamp(data.createdAt),
              id: repoLastDoc.id,
              postId: repoLastDoc.id,
            };
          } else {
            nextCursor = {
              createdAt: this.normalizeTimestamp(repoLastDoc.createdAt),
              id: repoLastDoc.id,
              postId: repoLastDoc.id,
            };
          }
        }

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

        // Build cursor from repository order for stable pagination.
        const repoLastDoc = result.lastDoc;
        let nextCursor = null;
        if (repoLastDoc) {
          if (typeof repoLastDoc.data === 'function') {
            const data = repoLastDoc.data();
            nextCursor = {
              createdAt: this.normalizeTimestamp(data.createdAt),
              id: repoLastDoc.id,
              postId: repoLastDoc.id,
            };
          } else {
            nextCursor = {
              createdAt: this.normalizeTimestamp(repoLastDoc.createdAt),
              id: repoLastDoc.id,
              postId: repoLastDoc.id,
            };
          }
        }

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
    * 
    * PROGRESSIVE RADIUS:
    * - First: Return posts within 50km, sorted nearest first
    * - When 50km exhausted: Expand to 1500km, still sorted nearest first
    */
   async getHybridFeed({
      latitude,
      longitude,
      pageSize = 20,
      cursor = null, 
      mediaType = null,
      userContext = null
    }) {
      try {
        // 🔥 PROGRESSIVE RADIUS
        // First return posts within 50km
        // When those are exhausted, expand to 1500km
        const NEARBY_RADIUS_KM = 50.0;
        const MAX_RADIUS_KM = 1500.0;
        const MAX_FETCH_ATTEMPTS = 5;
        
        const userLat = parseFloat(latitude);
        const userLng = parseFloat(longitude);
        const hasUserLocation = !isNaN(userLat) && !isNaN(userLng);
        
        // Check if we're expanding radius based on cursor hint
        const isExpandingRadius = cursor?._expandRadius === true;
        const currentRadius = isExpandingRadius ? MAX_RADIUS_KM : NEARBY_RADIUS_KM;
        
        // Collect posts with distances
        let allPostsWithDistance = [];
        let currentCursor = cursor;
        let hasMoreGlobal = true;
        let lastDoc = null;
        let attempts = 0;
        
        // Fetch batches
        while (allPostsWithDistance.length < pageSize && hasMoreGlobal && attempts < MAX_FETCH_ATTEMPTS) {
          attempts++;
          
          const result = await postRepository.getGlobalFeed({
            pageSize: pageSize * 2,
            lastDocSnapshot: currentCursor,
            mediaType
          });
          
          let posts = result.posts;
          hasMoreGlobal = result.hasMore;
          lastDoc = result.lastDoc;
          
          if (posts.length === 0) break;
          
          if (userContext && userContext.mutedUserIds) {
            posts = posts.filter(p => !userContext.mutedUserIds.has(p.authorId));
          }
          
          // Calculate distances
          posts = posts.map(post => {
            let distance = Infinity;
            if (hasUserLocation) {
              const lat = post.latitude ?? post.location?.lat;
              const lng = post.longitude ?? post.location?.lng;
              if (lat != null && lng != null) {
                distance = this.calculateDistance(userLat, userLng, lat, lng);
              }
            }
            return { ...post, normalizedCreatedAt: this.normalizeTimestamp(post.createdAt), distance };
          });
          
          // Filter by current radius
          const postsInRadius = posts.filter(post => post.distance <= currentRadius);
          allPostsWithDistance = [...allPostsWithDistance, ...postsInRadius];
          
          // Update cursor
          if (lastDoc) {
            if (typeof lastDoc.data === 'function') {
              const data = lastDoc.data();
              currentCursor = { createdAt: this.normalizeTimestamp(data.createdAt), id: lastDoc.id, postId: lastDoc.id };
            } else {
              currentCursor = { createdAt: this.normalizeTimestamp(lastDoc.createdAt), id: lastDoc.id, postId: lastDoc.id };
            }
          }
        }
        
        // Sort by distance
        allPostsWithDistance.sort((a, b) => {
          if (a.distance !== b.distance) return a.distance - b.distance;
          return b.normalizedCreatedAt - a.normalizedCreatedAt;
        });
        
        // Take page size
        const finalPosts = allPostsWithDistance.slice(0, pageSize);
        const remainingCount = allPostsWithDistance.length - finalPosts.length;
        
        // 🔥 DETERMINE HAS MORE LOGIC
        let effectiveHasMore = false;
        let nextCursor = null;
        let shouldExpandRadius = false;
        
        logger.info({
          currentRadius,
          finalPostsLength: finalPosts.length,
          remainingCount,
          hasMoreGlobal,
          NEARBY_RADIUS_KM,
          MAX_RADIUS_KM
        }, '[FeedService] DEBUG hasMore logic inputs');
        
        if (remainingCount > 0) {
          // More posts available in current radius
          effectiveHasMore = true;
          const lastPost = finalPosts[finalPosts.length - 1];
          nextCursor = { createdAt: lastPost.normalizedCreatedAt, id: lastPost.id, postId: lastPost.id };
          logger.info('[FeedService] DEBUG: remainingCount > 0, hasMore=true');
        } else if (currentRadius === NEARBY_RADIUS_KM) {
          // 50km radius exhausted - EXPAND to 1500km
          effectiveHasMore = true;
          shouldExpandRadius = true;
          nextCursor = currentCursor ? { ...currentCursor, _expandRadius: true } : { _expandRadius: true };
          logger.info('[FeedService] DEBUG: expanding from 50km to 1500km');
        } else if (currentRadius === MAX_RADIUS_KM) {
          // At max radius (1500km)
          if (finalPosts.length > 0 && hasMoreGlobal) {
            effectiveHasMore = true;
            const lastPost = finalPosts[finalPosts.length - 1];
            nextCursor = { createdAt: lastPost.normalizedCreatedAt, id: lastPost.id, postId: lastPost.id };
            logger.info('[FeedService] DEBUG: 1500km with posts, hasMore=true');
          } else {
            // No posts within 1500km - STOP LOOPING
            effectiveHasMore = false;
            nextCursor = null;
            logger.info('[FeedService] DEBUG: 1500km NO POSTS - STOPPING, hasMore=false');
          }
        } else {
          // Should not reach here
          effectiveHasMore = false;
          nextCursor = null;
          logger.info({ currentRadius }, '[FeedService] DEBUG: UNEXPECTED radius - stopping');
        }

        logger.info({
          attempts,
          radiusUsed: currentRadius,
          postsFound: allPostsWithDistance.length,
          returned: finalPosts.length,
          nearestDistance: finalPosts.length > 0 ? finalPosts[0].distance.toFixed(1) : null,
          willExpandRadius: shouldExpandRadius,
          hasMore: effectiveHasMore
        }, '[FeedService] Progressive radius feed');

        return { posts: finalPosts, nextCursor, hasMore: effectiveHasMore, pagination: { nextCursor, hasMore: effectiveHasMore } };
      } catch (error) {
        logger.error({ latitude, longitude, error }, '[FeedService] Error getting hybrid feed');
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
