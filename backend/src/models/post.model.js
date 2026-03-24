/**
 * Post Model - Type definitions and schema for posts
 * 
 * This is the SINGLE SOURCE OF TRUTH for post data structure.
 * All repositories, services, and routes must conform to this.
 */

/**
 * @typedef {Object} Post
 * @property {string} id - Firestore document ID
 * @property {string} title - Post title (max 2000 chars)
 * @property {string} body - Post content (max 5000 chars)
 * @property {string} authorId - Author's Firebase UID
 * @property {string} authorName - Author's display name
 * @property {string} authorProfileImage - URL to author's profile pic
 * @property {string} city - City name
 * @property {string} country - Country name
 * @property {string} status - 'active', 'archived', 'deleted'
 * @property {string} visibility - 'public', 'private', 'friends'
 * @property {string} mediaType - 'none', 'image', 'video', 'audio'
 * @property {string} mediaUrl - URL to media content
 * @property {number} latitude - Geographic latitude
 * @property {number} longitude - Geographic longitude
 * @property {Object} location - {lat, lng} object
 * @property {string} geoHash - Geohash string (9 chars)
 * @property {number} likeCount - Current like count
 * @property {number} commentCount - Total comments
 * @property {number} viewCount - Total views
 * @property {number} engagementScore - Composite engagement metric
 * @property {string} category - Post category/topic
 * @property {Date} createdAt - Post creation timestamp
 * @property {Date} updatedAt - Last modification timestamp
 */

export const PostSchema = {
  id: 'string (Firestore ID)',
  title: 'string, max 2000',
  body: 'string, max 5000',
  authorId: 'string (Firebase UID)',
  authorName: 'string',
  authorProfileImage: 'string (URL) or null',
  city: 'string',
  country: 'string',
  status: 'enum: active|archived|deleted',
  visibility: 'enum: public|private|friends',
  mediaType: 'enum: none|image|video|audio',
  mediaUrl: 'string (URL) or null',
  latitude: 'number',
  longitude: 'number',
  location: '{ lat: number, lng: number }',
  geoHash: 'string (9 chars)',
  likeCount: 'number',
  commentCount: 'number',
  viewCount: 'number',
  engagementScore: 'number',
  category: 'string or null',
  createdAt: 'Firestore Timestamp',
  updatedAt: 'Firestore Timestamp'
};

/**
 * Map Firestore document to Post object
 * @param {Object} doc - Firestore document
 * @returns {Post}
 */
export function mapDocToPost(doc) {
  if (!doc.exists) return null;
  
  const data = doc.data();
  return {
    id: doc.id,
    title: data.title || '',
    body: data.body || '',
    authorId: data.authorId || '',
    authorName: data.authorName || 'Unknown',
    authorProfileImage: data.authorProfileImage || null,
    city: data.city || '',
    country: data.country || '',
    status: data.status || 'active',
    visibility: data.visibility || 'public',
    mediaType: data.mediaType || 'none',
    mediaUrl: data.mediaUrl || null,
    latitude: data.latitude || null,
    longitude: data.longitude || null,
    location: data.location || { lat: null, lng: null },
    geoHash: data.geoHash || '',
    likeCount: data.likeCount || 0,
    commentCount: data.commentCount || 0,
    viewCount: data.viewCount || 0,
    engagementScore: data.engagementScore || 0,
    category: data.category || null,
    createdAt: data.createdAt || null,
    updatedAt: data.updatedAt || null
  };
}

/**
 * Validate post data before saving
 * @param {Object} post - Post object to validate
 * @returns {Object} { valid: boolean, errors: string[] }
 */
export function validatePost(post) {
  const errors = [];

  if (!post.title || typeof post.title !== 'string' || post.title.length > 2000) {
    errors.push('title must be a non-empty string, max 2000 chars');
  }

  if (!post.body || typeof post.body !== 'string' || post.body.length > 5000) {
    errors.push('body must be a non-empty string, max 5000 chars');
  }

  if (!post.authorId || typeof post.authorId !== 'string') {
    errors.push('authorId is required');
  }

  if (post.visibility && !['public', 'private', 'friends'].includes(post.visibility)) {
    errors.push('visibility must be one of: public, private, friends');
  }

  if (post.status && !['active', 'archived', 'deleted'].includes(post.status)) {
    errors.push('status must be one of: active, archived, deleted');
  }

  if (post.mediaType && !['none', 'image', 'video', 'audio'].includes(post.mediaType)) {
    errors.push('mediaType must be one of: none, image, video, audio');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}
