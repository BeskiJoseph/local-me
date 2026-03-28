/**
 * Post Repository - SINGLE SOURCE OF TRUTH for all post Firestore queries
 * 
 * This repository encapsulates ALL database access for posts.
 * No other file should directly query the 'posts' collection.
 * All queries go through this layer for:
 * - Consistency: Same sorting, filtering, pagination logic everywhere
 * - Maintainability: Changes to queries happen in one place
 * - Testability: Easier to mock for unit tests
 * - Security: Centralized validation before DB access
 */

import { db } from '../config/firebase.js';
import admin from 'firebase-admin';
import { mapDocToPost, validatePost } from '../models/post.model.js';
import logger from '../utils/logger.js';

class PostRepository {
  /**
   * Get a single post by ID
   * @param {string} postId
   * @returns {Promise<Object|null>}
   */
  async getPostById(postId) {
    try {
      const doc = await db.collection('posts').doc(postId).get();
      return mapDocToPost(doc);
    } catch (error) {
      logger.error({ postId, error }, '[PostRepo] Error fetching post by ID');
      throw error;
    }
  }

  /**
   * Create a new post
   * @param {Object} postData - Post content
   * @returns {Promise<{id: string, ...postData}>}
   */
  async createPost(postData) {
    // Validate before saving
    const validation = validatePost(postData);
    if (!validation.valid) {
      throw new Error(`Invalid post data: ${validation.errors.join(', ')}`);
    }

    try {
      const docRef = db.collection('posts').doc();
      const postToSave = {
        ...postData,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await docRef.set(postToSave);
      
      return {
        id: docRef.id,
        ...postToSave
      };
    } catch (error) {
      logger.error({ postData, error }, '[PostRepo] Error creating post');
      throw error;
    }
  }

  /**
   * Update an existing post
   * @param {string} postId
   * @param {Object} updates - Fields to update
   * @returns {Promise<Object>}
   */
  async updatePost(postId, updates) {
    try {
      const updateData = {
        ...updates,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      };

      await db.collection('posts').doc(postId).update(updateData);
      
      // Return updated post
      return this.getPostById(postId);
    } catch (error) {
      logger.error({ postId, updates, error }, '[PostRepo] Error updating post');
      throw error;
    }
  }

  /**
   * Delete a post (soft delete via status field)
   * @param {string} postId
   * @returns {Promise<void>}
   */
  async deletePost(postId) {
    try {
      await db.collection('posts').doc(postId).update({
        status: 'deleted',
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    } catch (error) {
      logger.error({ postId, error }, '[PostRepo] Error deleting post');
      throw error;
    }
  }

  /**
   * CRITICAL: Get local feed using geohash with cursor pagination
   * 
   * This is THE query that filters by geographic location.
   * PRODUCTION-GRADE REQUIREMENTS:
   *   - Ordering: createdAt DESC (primary) + __name__ DESC (secondary)
   *   - Pagination: Firestore startAfter with real DocumentSnapshot
   *   - Cursor Format: { createdAt, postId, authorName } for client-side handling
   *   - No Duplicates: Deterministic ordering + hasMore via extra row fetch
   *   - Graceful Fallback: If cursor post deleted, skip gracefully
   */
   async getLocalFeed({
     geoHashMin,
     geoHashMax,
     pageSize = 20,
     lastDocSnapshot = null,
     mediaType = null
   }) {
     try {
        // 🔥 CLEAN LOCAL FEED: No geoHash inequality, no distance orderBy
        // Frontend handles ALL distance sorting — backend just returns recent posts
        let query = db.collection('posts')
          .where('visibility', '==', 'public')
          .where('status', '==', 'active');

        if (mediaType && mediaType !== 'all') {
          query = query.where('mediaType', '==', mediaType);
        }

        // ✅ ONLY these two orderBy — nothing else
        query = query
          .orderBy('createdAt', 'desc')
          .orderBy(admin.firestore.FieldPath.documentId(), 'desc');

        // Cursor pagination — MUST be applied BEFORE limit
        if (lastDocSnapshot) {
          try {
            const createdAtValue = lastDocSnapshot.createdAt instanceof admin.firestore.Timestamp 
              ? lastDocSnapshot.createdAt 
              : admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
            const docId = lastDocSnapshot.postId || lastDocSnapshot.id;
            
            if (createdAtValue && docId) {
              query = query.startAfter(createdAtValue, docId);
              console.log(`[PostRepo] ✅ CURSOR APPLIED: startAfter(${createdAtValue.toMillis()}, ${docId})`);
            } else {
              console.log(`[PostRepo] ⚠️ CURSOR INCOMPLETE: createdAt=${createdAtValue}, docId=${docId}`);
            }
          } catch (err) {
            console.log(`[PostRepo] ❌ CURSOR ERROR:`, err.message);
          }
        } else {
          console.log('[PostRepo] 📄 No cursor — fetching from beginning');
        }

        query = query.limit(pageSize + 1);

        const snapshot = await query.get();
        console.log(`[PostRepo] Local feed fetched: ${snapshot.size} posts (pageSize=${pageSize})`);
        const docs = snapshot.docs;

        const hasMore = docs.length > pageSize;
        const finalDocs = docs.slice(0, pageSize);
        let posts = finalDocs.map(doc => mapDocToPost(doc));
        if (geoHashMin && geoHashMax) {
          posts = posts.filter(post => {
            if (!post.geoHash) return false;
            return post.geoHash >= geoHashMin && post.geoHash <= geoHashMax;
          });
        }

        // 🔥 CRITICAL: lastDoc is from FIRESTORE ORDER (createdAt DESC)
        // NOT from any re-sorted order.
        const lastDoc = finalDocs.length > 0 ? finalDocs[finalDocs.length - 1] : null;

        return {
          posts,
          lastDoc,
          hasMore,
          totalFetched: posts.length
        };
     } catch (error) {
       logger.error({ error }, '[PostRepo] Error fetching local feed');
       throw error;
     }
   }

    /**
     * Get global trending feed (no location filter)
     * 
     * PRODUCTION-GRADE PAGINATION:
     *   - Cursor Format: { createdAt, postId, authorName }
     *   - Uses Firestore startAfter with real DocumentSnapshot
     *   - Deterministic ordering prevents duplicates across pages
     */
    async getGlobalFeed({
      pageSize = 20,
      lastDocSnapshot = null,
      mediaType = null,
      afterDate = null
    }) {
      try {
        let query = db.collection('posts')
          .where('visibility', '==', 'public')
          .where('status', '==', 'active');

        if (mediaType && mediaType !== 'all') {
          query = query.where('mediaType', '==', mediaType);
        }

        // If looking for posts after a certain date (for trending)
        if (afterDate) {
          query = query.where('createdAt', '>=', afterDate);
        }

        // DETERMINISTIC ORDERING: createdAt DESC
        query = query
          .orderBy('createdAt', 'desc')
          .orderBy(admin.firestore.FieldPath.documentId(), 'desc') // Deterministic secondary sort
          .limit(pageSize + 1);

        // CURSOR PAGINATION: values fallback
        if (lastDocSnapshot) {
          if (lastDocSnapshot._document) {
            // 🔥 CRITICAL: Extract field values, don't pass document snapshot alone
            const createdAtValue = lastDocSnapshot.createdAt instanceof admin.firestore.Timestamp 
              ? lastDocSnapshot.createdAt 
              : admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
            const docId = lastDocSnapshot.id;
            query = query.startAfter(createdAtValue, docId);
            logger.info({ docId }, '[PostRepo] 🔥 Global: Using DocumentSnapshot field values: startAfter(createdAt, docId)');
          } else if (lastDocSnapshot.createdAt && (lastDocSnapshot.postId || lastDocSnapshot.id)) {
            try {
              const targetId = lastDocSnapshot.postId || lastDocSnapshot.id;
              const realDoc = await db.collection('posts').doc(targetId).get();
              if (realDoc.exists) {
                // 🔥 CRITICAL: Extract field values, don't pass document snapshot
                const createdAtValue = realDoc.get('createdAt');
                query = query.startAfter(createdAtValue, realDoc.id);
                logger.info({ docId: realDoc.id }, '[PostRepo] 🔥 Global: Resolved doc found - using COMPOUND startAfter(createdAt, docId)');
              } else {
                // FALLBACK: Use COMPOUND field values matching the orderBy sequence
                // orderBy('createdAt', 'desc').orderBy(docId, 'desc')
                // MUST use startAfter(createdAtDate, docId) not just createdAtDate
                const createdAtDate = lastDocSnapshot.createdAt instanceof admin.firestore.Timestamp 
                  ? lastDocSnapshot.createdAt 
                  : admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
                
                const docId = lastDocSnapshot.postId || lastDocSnapshot.id;
                query = query.startAfter(createdAtDate, docId);
                logger.info({ 
                  postId: docId,
                  createdAt: createdAtDate
                }, '[PostRepo] 🔥 Global: COMPOUND startAfter(createdAt, docId)');
              }
            } catch (err) {
              const createdAtDate = admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
              const docId = lastDocSnapshot.postId || lastDocSnapshot.id;
              query = query.startAfter(createdAtDate, docId);
              logger.warn({ err, postId: docId }, '[PostRepo] 🔥 Global: Error resolving doc, using COMPOUND values');
            }
          }
        }

        const snapshot = await query.get();
        console.log(`[PostRepo] Global feed snapshot size: ${snapshot.size}`);
        const docs = snapshot.docs;

        // Determine hasMore
        const hasMore = docs.length > pageSize;
        const posts = docs.slice(0, pageSize).map(doc => mapDocToPost(doc));

        return {
          posts,
          lastDoc: docs.length > 0 ? docs[Math.min(docs.length - 1, pageSize - 1)] : null,
          hasMore,
          totalFetched: posts.length
        };
      } catch (error) {
        logger.error({ error }, '[PostRepo] Error fetching global feed');
        throw error;
      }
    }

    /**
     * Get filtered feed (by author, category, city, etc.)
     * 
     * PRODUCTION-GRADE PAGINATION:
     *   - Ordering: createdAt DESC (primary) + __name__ DESC (secondary)
     *   - Cursor Format: { createdAt, postId, authorName }
     *   - Firestore startAfter with real DocumentSnapshot
     *   - Deterministic ordering prevents duplicates/jumping
     */
    async getFilteredFeed({
      authorId = null,
      category = null,
      city = null,
      country = null,
      pageSize = 20,
      lastDocSnapshot = null,
      mediaType = null
    }) {
      try {
        let query = db.collection('posts')
          .where('visibility', '==', 'public')
          .where('status', '==', 'active');

        if (authorId) query = query.where('authorId', '==', authorId);
        if (category) query = query.where('category', '==', category);
        if (city) query = query.where('city', '==', city);
        if (country) query = query.where('country', '==', country);
        if (mediaType && mediaType !== 'all') query = query.where('mediaType', '==', mediaType);

        // DETERMINISTIC ORDERING: createdAt DESC + docId DESC
        query = query
          .orderBy('createdAt', 'desc')
          .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
          .limit(pageSize + 1);

        // CURSOR PAGINATION: values fallback
        if (lastDocSnapshot) {
          if (lastDocSnapshot._document) {
            // 🔥 CRITICAL: Extract field values, don't pass document snapshot alone
            const createdAtValue = lastDocSnapshot.createdAt instanceof admin.firestore.Timestamp 
              ? lastDocSnapshot.createdAt 
              : admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
            const docId = lastDocSnapshot.id;
            query = query.startAfter(createdAtValue, docId);
            logger.info({ docId }, '[PostRepo] 🔥 Filtered: Using DocumentSnapshot field values: startAfter(createdAt, docId)');
          } else if (lastDocSnapshot.createdAt && (lastDocSnapshot.postId || lastDocSnapshot.id)) {
            try {
              const targetId = lastDocSnapshot.postId || lastDocSnapshot.id;
              const realDoc = await db.collection('posts').doc(targetId).get();
              if (realDoc.exists) {
                // 🔥 CRITICAL: Extract field values, don't pass document snapshot
                const createdAtValue = realDoc.get('createdAt');
                query = query.startAfter(createdAtValue, realDoc.id);
                logger.info({ docId: realDoc.id }, '[PostRepo] 🔥 Filtered: Resolved doc found - using COMPOUND startAfter(createdAt, docId)');
              } else {
                // FALLBACK: Use COMPOUND field values matching the orderBy sequence
                const createdAtDate = lastDocSnapshot.createdAt instanceof admin.firestore.Timestamp 
                  ? lastDocSnapshot.createdAt 
                  : admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
                
                const docId = lastDocSnapshot.postId || lastDocSnapshot.id;
                query = query.startAfter(createdAtDate, docId);
                logger.info({ postId: docId }, '[PostRepo] 🔥 Filtered: COMPOUND startAfter(createdAt, docId)');
              }
            } catch (err) {
              const createdAtDate = admin.firestore.Timestamp.fromMillis(Number(lastDocSnapshot.createdAt));
              const docId = lastDocSnapshot.postId || lastDocSnapshot.id;
              query = query.startAfter(createdAtDate, docId);
              logger.warn({ err, postId: docId }, '[PostRepo] 🔥 Filtered: Error resolving doc, using COMPOUND values');
            }
          }
        }

        const snapshot = await query.get();
        const docs = snapshot.docs;

        const hasMore = docs.length > pageSize;
        const posts = docs.slice(0, pageSize).map(doc => mapDocToPost(doc));

        return {
          posts,
          lastDoc: docs.length > 0 ? docs[Math.min(docs.length - 1, pageSize - 1)] : null,
          hasMore,
          totalFetched: posts.length
        };
      } catch (error) {
        logger.error({
          authorId, category, city, country, error
        }, '[PostRepo] Error fetching filtered feed');
        throw error;
      }
    }

  /**
   * Get posts by author (for profile view)
   */
  async getPostsByAuthor(authorId, { pageSize = 20, lastDocSnapshot = null } = {}) {
    return this.getFilteredFeed({
      authorId,
      pageSize,
      lastDocSnapshot
    });
  }

  /**
   * Search posts by title/body (basic text search)
   * 
   * NOTE: This uses array-contains on searchTokens.
   * Ensure searchTokens are generated consistently in createPost/updatePost.
   */
  async searchPosts(searchQuery, { pageSize = 20, lastDocSnapshot = null } = {}) {
    try {
      const normalizedQuery = searchQuery.toLowerCase().trim();
      if (normalizedQuery.length < 3) {
        throw new Error('Search query must be at least 3 characters');
      }

      let query = db.collection('posts')
        .where('visibility', '==', 'public')
        .where('status', '==', 'active')
        .where('searchTokens', 'array-contains', normalizedQuery);

      query = query
        .orderBy('createdAt', 'desc')
        .orderBy(admin.firestore.FieldPath.documentId(), 'desc')
        .limit(pageSize);

      if (lastDocSnapshot) {
        query = query.startAfter(lastDocSnapshot);
      }

      const snapshot = await query.get();
      const posts = snapshot.docs.map(doc => mapDocToPost(doc));

      return {
        posts,
        lastDoc: snapshot.docs.length > 0 ? snapshot.docs[snapshot.docs.length - 1] : null,
        hasMore: snapshot.docs.length >= pageSize
      };
    } catch (error) {
      logger.error({ searchQuery, error }, '[PostRepo] Error searching posts');
      throw error;
    }
  }

  /**
   * Bulk increment like count
   * Used for fast updates from interaction service
   */
  async incrementLikeCount(postId, delta = 1) {
    try {
      await db.collection('posts').doc(postId).update({
        likeCount: admin.firestore.FieldValue.increment(delta)
      });
    } catch (error) {
      logger.error({ postId, delta, error }, '[PostRepo] Error incrementing likes');
      throw error;
    }
  }

  /**
   * Bulk get multiple posts (for efficiency)
   */
  async getPostsByIds(postIds) {
    if (!postIds || postIds.length === 0) return [];

    try {
      // Firestore 'in' query limited to 30 items
      const chunks = [];
      for (let i = 0; i < postIds.length; i += 30) {
        chunks.push(postIds.slice(i, i + 30));
      }

      const results = [];
      for (const chunk of chunks) {
        const snapshot = await db.collection('posts')
          .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
          .get();

        results.push(...snapshot.docs.map(doc => mapDocToPost(doc)));
      }

      return results;
    } catch (error) {
      logger.error({ postIds, error }, '[PostRepo] Error bulk fetching posts');
      throw error;
    }
  }
}

export default new PostRepository();
