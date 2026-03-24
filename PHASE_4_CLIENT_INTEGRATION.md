# Phase 4: Client Integration Guide

**Hybrid Feed API** - How to integrate ranking + merge feature into mobile/web clients

---

## Quick Start

### 1. Update Your Feed Request

**Old (single-source feed)**:
```javascript
// Before: Only global posts
const response = await fetch('/api/posts?feedType=global&limit=20');
```

**New (hybrid merged + ranked feed)**:
```javascript
// After: Local + global merged + ranked
const response = await fetch(
  '/api/posts?feedType=hybrid&lat=37.7749&lng=-122.4194&limit=20'
);
```

### 2. Handle Response (New `score` Field)

```javascript
const { data, pagination } = response.json();

// Posts now have score field
data.forEach(post => {
  console.log(`Post ${post.id} has score ${post.score.toFixed(2)}`);
  // Score ranges 0-1, already sorted (highest first)
});

// Access debug info
console.log('Merge breakdown:', pagination.mergeInfo);
// {
//   localPosts: 12,
//   globalPosts: 8,
//   mergedTotal: 20,
//   dedupedTotal: 20,
//   rankedTotal: 20,
//   finalTotal: 20
// }
```

### 3. Pagination (Unchanged)

```javascript
// Build nextCursor from pagination
const cursor = pagination.nextCursor;

// Page 2 request
const page2 = await fetch(
  `/api/posts?feedType=hybrid&lat=37.7749&lng=-122.4194&limit=20&cursor=${btoa(JSON.stringify(cursor))}`
);

// Continue pagination normally
// Note: Posts on page 2 might have different score than on page 1 (this is OK!)
```

---

## API Reference

### Endpoint
```
GET /api/posts
```

### Parameters

| Name | Type | Required | Example | Notes |
|------|------|----------|---------|-------|
| `feedType` | string | Yes | `hybrid` | Must be `hybrid` for ranking |
| `lat` | number | Yes | `37.7749` | User latitude (required for ranking) |
| `lng` | number | Yes | `-122.4194` | User longitude (required for ranking) |
| `limit` | number | No | `20` | Posts per page (max 50, default 20) |
| `cursor` | string | No | (base64) | For pagination (base64 encoded cursor object) |
| `mediaType` | string | No | `photo` | Filter by media type |

### Response Format

```javascript
{
  success: boolean,
  data: [
    {
      id: "post-abc123",
      title: "Post title",
      description: "Post description",
      
      // Core fields
      likeCount: 42,
      commentCount: 5,
      viewCount: 1200,
      
      // Location
      latitude: 37.775,
      longitude: -122.419,
      
      // Timestamps
      createdAt: 1711270000000,      // Milliseconds since epoch
      updatedAt: 1711270000000,
      
      // Author
      authorId: "user-abc123",
      authorName: "john_doe",
      authorAvatar: "https://...",
      
      // NEW IN PHASE 4
      score: 0.856,                 // Ranking score (0-1)
      
      // Media
      media: [{
        type: "photo",
        url: "https://..."
      }],
      
      // Status
      visibility: "public",
      status: "active",
      
      // User engagement
      liked: false,
      bookmarked: false
    },
    // ... 19 more posts
  ],
  
  pagination: {
    nextCursor: {
      createdAt: 1711270000000,
      postId: "post-abc123",
      authorName: "john_doe"
    },
    hasMore: true,
    count: 20,
    
    // NEW IN PHASE 4: Debug transparency
    mergeInfo: {
      localPosts: 12,        // Posts from geo-search (user's area)
      globalPosts: 8,        // Posts from global search (fallback)
      mergedTotal: 20,       // After merge
      dedupedTotal: 20,      // After removing duplicates
      rankedTotal: 20,       // After ranking computation
      finalTotal: 20         // Final returned count
    },
    
    algorithm: "ranking"    // Indicates ranking was applied
  }
}
```

---

## Understanding the Ranking Score

### Score Computation
```
score = (recency × 0.5) + (engagement × 0.3) + (distance × 0.2)
```

| Component | Weight | Formula | Example |
|-----------|--------|---------|---------|
| **Recency** | 50% | `1 / (1 + hoursOld)` | 1 hour old = 0.5, 0 hours old = 1.0 |
| **Engagement** | 30% | `min((likes + comments×2 + views×0.1) / 100, 1)` | 100 engagement = 1.0 |
| **Distance** | 20% | `1 / (1 + distanceKm)` | 1km away = 0.5, 0km away = 1.0 |

### Score Examples
```javascript
// Hypothetical post
const post1 = {
  createdAt: Date.now(),        // Just now
  likeCount: 50,
  commentCount: 10,
  viewCount: 500,
  latitude: 37.7749,
  longitude: -122.4194
};
// User at 37.7749, -122.4194 (same location)
// Score: (1.0 × 0.5) + (0.7 × 0.3) + (1.0 × 0.2) = 0.91 (very high!)

const post2 = {
  createdAt: Date.now() - (24 * 60 * 60 * 1000),  // 24 hours old
  likeCount: 5,
  commentCount: 0,
  viewCount: 10,
  latitude: 40.7128,  // NYC
  longitude: -74.0060
};
// User at SF (1500km away)
// Score: (0.04 × 0.5) + (0.06 × 0.3) + (0.0007 × 0.2) ≈ 0.04 (very low)
```

### What Different Scores Mean
- **0.8-1.0**: Fresh, local, highly engaging posts (top of feed)
- **0.5-0.8**: Mix of recency/engagement/location (middle of feed)
- **0.2-0.5**: Older or far away posts (bottom of feed)
- **< 0.2**: Very old or very far away posts (rarely shown)

---

## Comparison: Old vs. New Feeds

### feedType=local
```
✓ Only posts from user's geographic area
✓ Deterministic ordering (always same order for same location)
✓ NO ranking applied
✓ Good for: Browsing neighborhood
```

### feedType=global
```
✓ All public posts worldwide
✓ Deterministic ordering
✓ NO ranking applied
✓ Good for: Discovering distant content
```

### feedType=hybrid (NEW)
```
✓ Merges local + global (smart mix)
✓ Ranked by recency + engagement + location
✓ Personalized to user location
✓ Good for: Main feed (best of both worlds)
```

---

## Implementation Checklist

- [ ] Update feed request to use `feedType=hybrid` with coordinates
- [ ] Parse `score` field from response (optional: show it for debug)
- [ ] Handle `mergeInfo` for transparency
- [ ] Update pagination to handle cursor (base64 encode/decode)
- [ ] Test with 5-10 pages of scrolling
- [ ] Verify no duplicates across pages
- [ ] Monitor response times (should be < 500ms)
- [ ] Deploy to staging for user testing
- [ ] Collect UX feedback (do users like ranked feed?)
- [ ] Deploy to production

---

## Troubleshooting

### Q: Posts appear in different order on page 2?
**A**: Expected! Posts on page 2 are from a different time period, so recency scores change. Newest posts rank highest.

### Q: Some posts have score close to 0?
**A**: They're far away or very old. Either:
- Move user's location (location changed)
- Scroll more (feed shows best content first)
- Check if post is public/active

### Q: Missing `mergeInfo` in response?
**A**: If using older backend version, it won't be present. Update to commit `6927e5d+`.

### Q: What if I don't want ranking?
**A**: Use `feedType=local` or `feedType=global` (both are deterministic, no ranking).

### Q: Can I customize ranking weights?
**A**: Yes! Edit `computeScore()` in `backend/src/services/feedService.js`:
```javascript
// Current: 0.5 + 0.3 + 0.2
// Try: 0.6 + 0.2 + 0.2 (more recency-focused)
// Or: 0.3 + 0.5 + 0.2 (more engagement-focused)
```

---

## Testing Checklist

### Manual Testing
```javascript
// Test 1: Get first page
const page1 = await fetch(
  '/api/posts?feedType=hybrid&lat=37.7749&lng=-122.4194&limit=20'
).then(r => r.json());

console.log('Page 1:', page1.data.length, 'posts');
console.log('Merge info:', page1.pagination.mergeInfo);

// Test 2: Get second page
const page2 = await fetch(
  `/api/posts?feedType=hybrid&lat=37.7749&lng=-122.4194&limit=20&cursor=${btoa(JSON.stringify(page1.pagination.nextCursor))}`
).then(r => r.json());

// Test 3: Verify no duplicates
const page1Ids = new Set(page1.data.map(p => p.id));
const page2Ids = new Set(page2.data.map(p => p.id));
const overlap = [...page1Ids].filter(id => page2Ids.has(id));
console.log('Duplicates:', overlap.length); // Should be 0
```

### Performance Testing
```javascript
// Measure response time
const start = Date.now();
const response = await fetch('/api/posts?feedType=hybrid&lat=X&lng=Y');
const duration = Date.now() - start;
console.log(`Response time: ${duration}ms`); // Should be < 500ms
```

---

## Migration Path

### If You're Currently Using `feedType=global`:

**Phase 1** (Week 1):
```javascript
// Update to hybrid (with user location)
const response = await fetch(
  `/api/posts?feedType=hybrid&lat=${userLat}&lng=${userLng}&limit=20`
);
```

**Phase 2** (Week 2):
```javascript
// A/B test: 50% users see hybrid, 50% see global
const usesHybrid = Math.random() < 0.5;
const feedType = usesHybrid ? 'hybrid' : 'global';

// Track: Do hybrid users spend more time? Like more posts?
logAnalytics({
  feedType,
  timeSpent: getTimeOnPage(),
  likes: getPostInteractions()
});
```

**Phase 3** (Week 3+):
```javascript
// Based on analytics, either:
// Option A: Full rollout to hybrid
// Option B: Keep global (users prefer it)
// Option C: Hybrid for some, global for others
```

---

## Response Time Breakdown

When you request `feedType=hybrid`, backend does:
1. Query local posts (geo-search): ~50-100ms
2. Query global posts: ~50-100ms
3. Merge + deduplicate: ~10ms (in-memory)
4. Compute rankings on 80 posts: ~20-50ms (score calculation)
5. Sort by score + limit: ~5ms
6. Build response: ~10-20ms

**Total: 150-300ms** (acceptable for feed endpoint)

---

## Success Metrics to Track

```javascript
// Track these metrics
analytics.track('feed_view', {
  feedType: 'hybrid',
  postsReturned: data.length,
  localPostCount: pagination.mergeInfo.localPosts,
  globalPostCount: pagination.mergeInfo.globalPosts,
  avgScore: data.reduce((a, p) => a + p.score, 0) / data.length,
  topScore: data[0].score,
  bottomScore: data[data.length - 1].score
});

// Track engagement
analytics.track('post_engagement', {
  postId: post.id,
  score: post.score,  // Did higher-score posts get more likes?
  liked: true,
  timeSpent: getTimeOnPost()
});
```

---

## Real-World Example

```javascript
// Mobile app - Refresh feed
async function refreshFeed() {
  const userLocation = await getUserLocation();
  
  const response = await fetch(
    `/api/posts?feedType=hybrid&lat=${userLocation.lat}&lng=${userLocation.lng}&limit=20`
  );
  
  const { data, pagination } = await response.json();
  
  // Show posts (already ranked by score)
  renderFeedPosts(data);
  
  // Save cursor for next page
  this.nextCursor = pagination.nextCursor;
  this.hasMore = pagination.hasMore;
  
  // Optional: Show ranking quality
  console.debug('Feed quality:', {
    localPosts: pagination.mergeInfo.localPosts,
    globalPosts: pagination.mergeInfo.globalPosts,
    avgScore: (data.reduce((a, p) => a + p.score, 0) / data.length).toFixed(2)
  });
}

// User scrolls to bottom
async function loadMorePosts() {
  if (!this.hasMore) return;
  
  const response = await fetch(
    `/api/posts?feedType=hybrid&lat=${userLocation.lat}&lng=${userLocation.lng}&limit=20&cursor=${btoa(JSON.stringify(this.nextCursor))}`
  );
  
  const { data, pagination } = await response.json();
  
  // Append to feed
  appendFeedPosts(data);
  
  // Update for next page
  this.nextCursor = pagination.nextCursor;
  this.hasMore = pagination.hasMore;
}
```

---

**Integration complete! Your app now uses intelligent, ranked feeds.** 🎉
