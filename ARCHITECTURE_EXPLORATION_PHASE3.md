# Phase 3 Backend Architecture Exploration
## Cursor Pagination Implementation Analysis

**Date**: March 24, 2026  
**Exploration Target**: Phase 3 Cursor Pagination Implementation

---

## 1. FILE PATHS AND LOCATIONS

### Core Components (Repository Pattern)

| Component | File Path | Purpose |
|-----------|-----------|---------|
| **FeedService** | `backend/src/services/feedService.js` | Business logic for feed generation & curation |
| **PostRepository** | `backend/src/repositories/postRepository.js` | Single source of truth for all post queries |
| **PostController** | `backend/src/controllers/postController.js` | HTTP request/response handling layer |
| **Post Model** | `backend/src/models/post.model.js` | Type definitions and validation |
| **Pagination Helper** | `backend/src/utils/paginationHelper.js` | Pagination utilities |
| **Posts Routes** | `backend/src/routes/posts.js` | Route definitions & session management |

---

## 2. CURRENT PAGINATION IMPLEMENTATION OVERVIEW

### Architecture Pattern: 3-Layer Design

```
HTTP Request (posts.js routes)
         ↓
PostController (HTTP handling, parameter parsing)
         ↓
FeedService (Business logic, filtering, enrichment)
         ↓
PostRepository (Database queries, single source of truth)
         ↓
Firestore Database
```

### Key Design Principles

1. **Separation of Concerns**: Each layer has a single responsibility
2. **Single Source of Truth**: All queries go through PostRepository
3. **Centralized Sorting**: All feeds use same ordering: `createdAt DESC` + `__name__ DESC`
4. **Composite Cursors**: Cursors are objects `{ createdAt, postId }` not strings

---

## 3. FEEDSERVICE PAGINATION LOGIC

**File**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\services\feedService.js`

### Three Feed Types Implemented

#### A. LOCAL FEED (getLocalFeed)
```javascript
Parameters:
  - latitude, longitude (user's coordinates)
  - geoHashMin, geoHashMax (pre-calculated bounds)
  - seenPostIds (Set of already-viewed posts)
  - pageSize (default 20, max 50)
  - lastDocSnapshot (composite cursor from previous page)
  - mediaType (optional filter)
  - userContext (user's likes, follows, mutes)

Returns:
  {
    posts: [Post[]],
    cursor: { createdAt: number, postId: string },
    hasMore: boolean,
    pagination: {
      cursor: object,
      hasMore: boolean,
      seenIds: string[] (last 500 IDs)
    }
  }
```

**Key Features**:
- Filters by geographic location using geohash
- Enriches posts with user interaction data (isLiked, isFollowing)
- Builds composite cursor from last post (createdAt + postId)
- Applies user preferences (muting, etc.)

#### B. GLOBAL FEED (getGlobalFeed)
```javascript
Parameters:
  - seenPostIds (Set)
  - pageSize (20 default)
  - lastDocSnapshot (composite cursor)
  - mediaType (optional)
  - userContext

Returns: Same as LOCAL FEED
```

**Key Features**:
- No geographic filtering
- Implements trending algorithm (72-hour window)
- Calculates trending scores: engagement + time decay
- Sorts by trending score after fetch

**Trending Score Calculation**:
```javascript
score = (baseScore + engagementMetric) * decayMultiplier
where:
  - baseScore = 100
  - engagement = likes + (comments * 2) + (views * 0.1)
  - decay = 0.95^hoursOld
```

#### C. FILTERED FEED (getFilteredFeed)
```javascript
Parameters:
  - authorId, category, city, country (filters)
  - seenPostIds, pageSize, lastDocSnapshot, mediaType, userContext

Returns: Same as LOCAL FEED
```

**Key Features**:
- Flexible filtering by author, category, location, media type
- Same pagination logic as other feeds

### Composite Cursor Generation

All three feeds generate cursors in this format:
```javascript
const lastPost = posts[posts.length - 1];
const compositeCursor = lastPost ? {
  createdAt: lastPost.createdAt.toMillis?.() || lastPost.createdAt || Date.now(),
  postId: lastPost.id
} : null;
```

---

## 4. POSTREPOSITORY QUERY METHODS

**File**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\repositories\postRepository.js`

### CRUD Operations

| Method | Purpose |
|--------|---------|
| `getPostById(postId)` | Fetch single post |
| `createPost(postData)` | Create new post with validation |
| `updatePost(postId, updates)` | Update post fields |
| `deletePost(postId)` | Soft delete (mark as deleted) |

### Feed Query Methods

#### 1. getLocalFeed() [Lines 115-180]

**Query Structure**:
```javascript
db.collection('posts')
  .where('visibility', '==', 'public')
  .where('status', '==', 'active')
  .where('geoHash', '>=', geoHashMin)
  .where('geoHash', '<=', geoHashMax)
  .where('mediaType', '==', mediaType)  // Optional
  .orderBy('createdAt', 'desc')
  .orderBy('__name__', 'desc')  // Tie-breaking
  .limit(pageSize + 1)  // Fetch extra to determine hasMore
  .startAfter(realDocSnapshot)  // Cursor pagination
```

**Cursor Handling**:
```javascript
if (lastDocSnapshot.createdAt && lastDocSnapshot.postId && !lastDocSnapshot._document) {
  // Composite cursor from client - fetch real DocumentSnapshot
  const realDoc = await db.collection('posts').doc(lastDocSnapshot.postId).get();
  query = query.startAfter(realDoc);
} else if (lastDocSnapshot._document) {
  // Already a real DocumentSnapshot
  query = query.startAfter(lastDocSnapshot);
}
```

**Returns**:
```javascript
{
  posts: Post[],           // Filtered to exclude seenPostIds
  lastDoc: DocumentSnapshot, // For further cursoring
  hasMore: boolean,        // docs.length > pageSize
  totalFetched: number
}
```

#### 2. getGlobalFeed() [Lines 188-254]

**Query Structure**:
```javascript
db.collection('posts')
  .where('visibility', '==', 'public')
  .where('status', '==', 'active')
  .where('createdAt', '>=', afterDate)  // 72-hour window
  .where('mediaType', '==', mediaType)  // Optional
  .orderBy('createdAt', 'desc')
  .orderBy('__name__', 'desc')
  .limit(pageSize + 1)
  .startAfter(realDocSnapshot)
```

**Differences from getLocalFeed**:
- No geohash filtering
- Has time window filter (72 hours for trending)
- Fetches `pageSize * 2` posts (FeedService will sort by trending)

#### 3. getFilteredFeed() [Lines 261-328]

**Query Structure**:
```javascript
db.collection('posts')
  .where('visibility', '==', 'public')
  .where('status', '==', 'active')
  .where('authorId', '==', authorId)      // Optional
  .where('category', '==', category)      // Optional
  .where('city', '==', city)              // Optional
  .where('country', '==', country)        // Optional
  .where('mediaType', '==', mediaType)    // Optional
  .orderBy('createdAt', 'desc')
  .orderBy('__name__', 'desc')
  .limit(pageSize + 1)
  .startAfter(realDocSnapshot)
```

### Supporting Methods

| Method | Purpose | Lines |
|--------|---------|-------|
| `getPostsByAuthor(authorId, opts)` | Profile view posts | 333-340 |
| `searchPosts(query, opts)` | Text search via searchTokens | 348-381 |
| `incrementLikeCount(postId, delta)` | Fast like count updates | 387-396 |
| `getPostsByIds(postIds)` | Bulk fetch (max 30 items) | 401-425 |

### Critical Ordering Rules

**ALL queries enforce**:
1. Primary sort: `createdAt DESC` (newest first)
2. Secondary sort: `__name__ DESC` (deterministic tie-breaking)
3. Extra fetch: Always `limit(pageSize + 1)` to detect if more exist

**Why**:
- Deterministic pagination (same results every time)
- Handles edge case where multiple posts have exact same timestamp
- Prevents duplicate posts across pages

---

## 5. POSTCONTROLLER ENDPOINTS

**File**: `C:\Users\beski\Downloads\testpro-main (1)\backend\src\controllers\postController.js`

### Endpoint Methods

#### A. getLocalFeed(req, res, next) [Lines 113-187]

**HTTP Flow**:
```
GET /api/posts?feedType=local&lat=X&lng=Y&limit=20&cursor=JSON
       ↓
Extract: lat, lng, limit, cursor, mediaType, sessionId
       ↓
Validate coordinates (geoService)
       ↓
Get user context (likes, follows, mutes)
       ↓
Parse composite cursor (JSON.parse)
       ↓
Calculate geohash bounds (precision 9)
       ↓
Call feedService.getLocalFeed()
       ↓
Return: { success, data: [posts], pagination: {...} }
```

**Query Pa
