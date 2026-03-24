# Phase 3 Cursor Pagination - Core Files Reference

## Quick Reference: File Paths and Key Information

### 1. FeedService
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\services\feedService.js`

**Lines of Code**: 244 total

**Methods**:
- `getLocalFeed()` (lines 44-100) - Geographically filtered feed
- `getGlobalFeed()` (lines 105-175) - Trending/global feed
- `getFilteredFeed()` (lines 180-241) - Author/category/location filtered feed

**Key Constants**:
- TRENDING_WINDOW_MS = 72 hours
- ENGAGEMENT_DECAY = 0.95 (per hour)
- BASE_TRENDING_SCORE = 100

**Composite Cursor Generation** (lines 81-86, 151-156, 218-223):
```javascript
const compositeCursor = lastPost ? {
  createdAt: lastPost.createdAt.toMillis?.() || lastPost.createdAt || Date.now(),
  postId: lastPost.id
} : null;
```

---

### 2. PostRepository
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\repositories\postRepository.js`

**Lines of Code**: 428 total

**Core Query Methods**:

1. **getLocalFeed()** (lines 115-180)
   - Ordering: `createdAt DESC, __name__ DESC`
   - Filters: geoHash range, visibility=public, status=active
   - Pagination: `startAfter(DocumentSnapshot)` via composite cursor

2. **getGlobalFeed()** (lines 188-254)
   - Ordering: `createdAt DESC, __name__ DESC`
   - Filters: time window (72 hours), visibility=public, status=active
   - Pagination: Same as getLocalFeed()

3. **getFilteredFeed()** (lines 261-328)
   - Ordering: `createdAt DESC, __name__ DESC`
   - Filters: authorId, category, city, country (all optional)
   - Pagination: Same as getLocalFeed()

**Composite Cursor Parsing** (lines 141-158, 216-233, 289-306):
```javascript
if (lastDocSnapshot.createdAt && lastDocSnapshot.postId && !lastDocSnapshot._document) {
  // Composite cursor from client
  const realDoc = await db.collection('posts').doc(lastDocSnapshot.postId).get();
  if (realDoc.exists) {
    query = query.startAfter(realDoc);
  } else {
    logger.warn('[PostRepo] Cursor post not found, starting from beginning');
  }
}
```

**Supporting Methods**:
- `getPostById()`, `createPost()`, `updatePost()`, `deletePost()`
- `getPostsByAuthor()`, `searchPosts()`, `getPostsByIds()`
- `incrementLikeCount()`

---

### 3. PostController
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\controllers\postController.js`

**Lines of Code**: 394 total

**HTTP Endpoints**:

1. **getLocalFeed()** (lines 113-187)
   - HTTP: `GET /api/posts?feedType=local&lat=X&lng=Y&limit=20&cursor=JSON`
   - Key logic: Validate coordinates → Get user context → Calculate geohash → Call service

2. **getGlobalFeed()** (lines 192-241)
   - HTTP: `GET /api/posts?feedType=global&limit=20&cursor=JSON`
   - Key logic: Get user context → Parse cursor → Call service

3. **getFilteredFeed()** (lines 246-301)
   - HTTP: `GET /api/posts?authorId=X&category=Y&limit=20&cursor=JSON`
   - Key logic: Extract filters → Get user context → Call service

**User Context Enrichment** (lines 73-79, 143-149, 210-216):
```javascript
posts = posts.map(post => ({
  ...post,
  isLiked: userContext.likedPostIds?.has(post.id) || false,
  isFollowing: userContext.followedUserIds?.has(post.authorId) || false
}));
```

**Other Methods**: `createPost()`, `getPost()`, `updatePost()`, `deletePost()`, `viewPost()`

---

### 4. Post Model
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\models\post.model.js`

**Lines of Code**: 133 total

**Schema Fields** (lines 35-59):
- Identity: id, authorId, authorName, authorProfileImage
- Content: title, body, category
- Location: city, country, latitude, longitude, location, geoHash
- Media: mediaType (enum), mediaUrl
- Status: status (active/archived/deleted), visibility (public/private/friends)
- Engagement: likeCount, commentCount, viewCount, engagementScore
- Timestamps: createdAt, updatedAt

**Key Functions**:

1. **mapDocToPost()** (lines 66-95)
   - Converts Firestore document to Post object
   - Provides defaults for all fields
   - Null-safe

2. **validatePost()** (lines 102-133)
   - Validates: title (max 2000), body (max 5000), authorId, visibility, status, mediaType
   - Returns: { valid: boolean, errors: string[] }

---

### 5. Pagination Helper
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\utils\paginationHelper.js`

**Lines of Code**: 60 total

**Functions**:
- `decodeCursor()` - Legacy (no longer used in Phase 3)
- `encodeCursor()` - Legacy
- `buildPaginationResponse()` - Builds response object
- `parseLimit()` - Validates and bounds page size

**Note**: Phase 3 moved away from these utilities to composite cursor objects in feedService.

---

### 6. Posts Routes
**File Path**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\routes\posts.js`

**Lines of Code**: 501 total

**Session Management** (lines 30-100):
- SESSION_SEEN Map stores per-session, per-feedType seenIds
- Prevents duplicate posts within same session
- 2-hour expiry, automatic cleanup
- URL overflow detection (logs warning if > 2000 chars)

**Feed Routing Logic** (lines 128-151):
```javascript
if (feedType === 'local' && lat && lng) {
  return postController.getLocalFeed(req, res, next);
} else if (authorId || category || city || country) {
  return postController.getFilteredFeed(req, res, next);
} else {
  return postController.getGlobalFeed(req, res, next);
}
```

**Core Routes**:
- POST /api/posts - Create
- GET /api/posts - Get feed (routed above)
- GET /api/posts/:id - Single post
- PUT /api/posts/:id - Update
- DELETE /api/posts/:id - Delete
- POST /api/posts/:id/view - Record view

**Legacy Endpoints** (lines 254-500):
- GET /api/posts/new-since
- POST/GET /api/posts/:id/messages
- GET /api/posts/:id/insights
- POST /api/posts/:id/report

---

## Pagination Flow Diagram

```
Client Request
    ↓
posts.js sessionMiddleware
    ↓ (tracks seenIds per feedType)
routes.js - Feed Router
    ↓ (routes to appropriate controller)
postController (parse params, get user context)
    ↓
feedService (apply filters, enrich posts, generate cursor)
    ↓
postRepository (execute Firestore query with startAfter)
    ↓
Firestore Database
    ↓
Response: { posts: [...], pagination: { cursor, hasMore, seenIds } }
```

---

## Composite Cursor Format

**Sent by Server**:
```javascript
{
  "pagination": {
    "cursor": {
      "createdAt": 1711270700000,      // Millisecond timestamp
      "postId": "post_xyz_123"         // Firestore doc ID
    },
    "hasMore": true,
    "seenIds": ["post1", "post2", ..., "post20"]
  }
}
```

**Received by Client**: 
```
/api/posts?limit=20&cursor={"createdAt":1711270700000,"postId":"post_xyz_123"}
```

**Parsed on Server**:
```javascript
let lastDocSnapshot = JSON.parse(decodeURIComponent(cursor));
// Converts to real DocumentSnapshot, applies startAfter()
```

---

## Key Pagination Rules

1. **All feeds use identical ordering**:
   ```javascript
   .orderBy('createdAt', 'desc')
   .orderBy('__name__', 'desc')
   ```

2. **hasMore detection**:
   ```javascript
   const hasMore = docs.length > pageSize;  // Fetch pageSize + 1
   const posts = docs.slice(0, pageSize);
   ```

3. **Cursor is only valid for that feed type**:
   - Local feed cursor ≠ Global feed cursor
   - Session tracks separate seenIds per feed

4. **Invalid cursors handled gracefully**:
   - If cursor post was deleted → start from beginning
   - Logs warning but doesn't crash

5. **Deduplication window**: 500 posts max
   - URL overflow (> 2000 chars) detected and logged
   - Client should switch to POST-based pagination for large datasets

---

## Phase 3 vs Phase 2 Improvements

| Aspect | Phase 2 | Phase 3 | Change |
|--------|---------|---------|--------|
| Cursor Format | `"post_xyz"` (string) | `{createdAt, postId}` (object) | ✅ Enhanced |
| Cursor Parsing | Fake object | Real DocumentSnapshot | ✅ Fixed |
| URL Overflow | Not handled | Detected + logged | ✅ Added |
| Tab Contamination | All seenIds mixed | Per-feedType separation | ✅ Fixed |
| Ordering | Deterministic ✅ | Deterministic ✅ | ✅ Maintained |
| hasMore Accuracy | ✅ | ✅ | ✅ Maint
