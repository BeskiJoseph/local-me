/**
 * Pagination Helper - Utilities for cursor-based pagination
 * 
 * Provides consistent pagination logic across all feeds.
 */

import logger from './logger.js';

/**
 * Decode pagination cursor
 * In our system, the cursor is simply the last post ID
 */
export function decodeCursor(cursor) {
  if (!cursor) return null;
  try {
    return cursor; // For ID-based cursors, it's just the ID
  } catch (error) {
    logger.warn({ cursor }, '[Pagination] Failed to decode cursor');
    return null;
  }
}

/**
 * Encode pagination cursor
 * In our system, the cursor is simply the post ID
 */
export function encodeCursor(postId) {
  if (!postId) return null;
  try {
    return postId;
  } catch (error) {
    logger.warn({ postId }, '[Pagination] Failed to encode cursor');
    return null;
  }
}

/**
 * Build pagination response object
 */
export function buildPaginationResponse(posts, hasMore, lastPostId = null) {
  return {
    cursor: lastPostId || (posts.length > 0 ? posts[posts.length - 1].id : null),
    hasMore,
    count: posts.length
  };
}

/**
 * Parse limit parameter (with bounds checking)
 */
export function parseLimit(limit, defaultLimit = 20, maxLimit = 50) {
  try {
    const parsed = parseInt(limit, 10);
    if (isNaN(parsed) || parsed < 1) return defaultLimit;
    if (parsed > maxLimit) return maxLimit;
    return parsed;
  } catch (error) {
    return defaultLimit;
  }
}
