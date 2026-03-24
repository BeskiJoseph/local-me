# 🔥 PHASE 3 PAGINATION TEST SUITE
## Production-Grade Cursor Pagination Validation

**Date**: March 24, 2026  
**Version**: 3.0 (Composite Cursors)

---

## TEST SCENARIOS

### TEST 1: Composite Cursor Generation
**What we're testing**: Cursors are now `{ createdAt, postId }` not just `postId`

**Test Steps**:
```bash
# Request first page of local feed
curl -X GET "http://localhost:8000/api/posts?feedType=local&lat=40.7128&lng=-74.0060&limit=10" \
  -H "Authorization: Bearer <token>"

# Expected Response:
{
  "success": true,
  "data": [
    { "id": "post1", "title": "...", "createdAt": 1711270800000 },
    { "id": "post2", "title": "...", "createdAt": 1711270795000 },
    ...
  ],
  "pagination": {
    "cursor": {
      "createdAt": 1711270750000,  # Last post's createdAt
      "postId": "post10"            # Last post's ID (composite!)
    },
    "hasMore": true,
    "seenIds": ["post1", "post2", ..., "post10"]
  }
}
```

**Verify**:
- ✅ `pagination.cursor` is an object with `createdAt` and `postId`
- ✅ `createdAt` is a millisecond timestamp
- ✅ `seenIds` array contains all 10 post IDs
- ✅ No `cursor` field is just a post ID ❌

---

### TEST 2: Cursor Pagination (No Duplicates)
**What we're testing**: Second page doesn't repeat posts from first page

**Test Steps**:
```bash
# Get first page
curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=5" \
  -H "Authorization: Bearer <token>"

# Response includes:
# pagination.cursor = { "createdAt": 1711270700000, "postId": "post5" }
# seenIds = ["post1", "post2", "post3", "post4", "post5"]

# Request second page with composite cursor
CURSOR='{"createdAt":1711270700000,"postId":"post5"}'
curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=5&cursor=$(echo -n $CURSOR | jq -r @uri)" \
  -H "Authorization: Bearer <token>"

# Expected Response:
# Posts 6-10 (NO posts 1-5)
# pagination.seenIds = ["post1", ..., "post10"]
```

**Verify**:
- ✅ Page 2 has 5 NEW posts (post6-post10)
- ✅ NO posts from page 1 appear again
- ✅ Posts sorted by `createdAt DESC` (newest first)

---

### TEST 3: Deterministic Ordering (Tie-Breaking)
**What we're testing**: Same `createdAt` posts use `__name__` (postId) for tie-breaking

**Test Steps**:
```bash
# In Firestore, create 3 posts with SAME createdAt but different IDs:
# post_zzz: createdAt = 1711270700000
# post_aaa: createdAt = 1711270700000
# post_mmm: createdAt = 1711270700000

# Request feed
curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=10" \
  -H "Authorization: Bearer <token>"

# Expected ordering:
# 1. post_zzz (createdAt DESC, then __name__ DESC = "post_zzz" > "post_mmm" > "post_aaa")
# 2. post_mmm
# 3. post_aaa
```

**Verify**:
- ✅ Posts with same `createdAt` are sorted by postId DESC
- ✅ Order is ALWAYS the same (deterministic)
- ✅ No random ordering

---

### TEST 4: URL Length Overflow (414 Handling)
**What we're testing**: Backend detects URL > 2000 chars and warns

**Test Steps**:
```bash
# Create 500 post IDs (will exceed 2000 chars)
SEEN_IDS="post1,post2,post3,...,post500"  # ~15KB when URL-encoded

curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=10&watchedIds=$SEEN_IDS" \
  -H "Authorization: Bearer <token>"

# Expected: 
# - Backend logs warning: "URL length exceeded 2000 chars (414 risk)"
# - Response still succeeds (capped at 500)
# - OR returns 414 if URL proxy rejects it
```

**Verify**:
- ✅ Backend detects and logs URL overflow
- ✅ seenIds capped at 500 items
- ✅ No crash or silent failure

---

### TEST 5: Per-Feed-Type Separation
**What we're testing**: seenIds are separated per feedType (no tab contamination)

**Test Steps**:
```bash
# Request LOCAL feed, get posts A1-A5
curl -X GET "http://localhost:8000/api/posts?feedType=local&lat=40.7128&lng=-74.0060&limit=5" \
  -H "Authorization: Bearer <token>"
# seenIds = [A1, A2, A3, A4, A5]

# Request GLOBAL feed with SESSION ID, get posts B1-B5
curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=5&sid=user123_session" \
  -H "Authorization: Bearer <token>"
# seenIds should be [B1, B2, B3, B4, B5], NOT include [A1-A5]

# Get next page of LOCAL feed
curl -X GET "http://localhost:8000/api/posts?feedType=local&lat=40.7128&lng=-74.0060&limit=5&cursor=..." \
  -H "Authorization: Bearer <token>"
# seenIds should be [A1-A10], INDEPENDENT of global seenIds
```

**Verify**:
- ✅ Local feed has its own seenIds
- ✅ Global feed has its own seenIds
- ✅ Posts from local feed don't appear marked as "seen" in global feed
- ✅ No cross-contamination between tabs

---

### TEST 6: hasMore Flag Accuracy
**What we're testing**: `hasMore` correctly indicates if more posts exist

**Test Steps**:
```bash
# Assume 23 total posts exist in database

# Request page 1: limit=10
# Response: hasMore = true (because 23 > 10)
# pagination.cursor = cursor_10

# Request page 2: limit=10&cursor=cursor_10
# Response: hasMore = true (because 13 > 10, we have 13 remaining)
# pagination.cursor = cursor_20

# Request page 3: limit=10&cursor=cursor_20
# Response: hasMore = false (only 3 posts left, < 10)
# posts = [post21, post22, post23]
```

**Verify**:
- ✅ Page 1: `hasMore = true`
- ✅ Page 2: `hasMore = true`
- ✅ Page 3: `hasMore = false`
- ✅ User knows when feed is exhausted

---

### TEST 7: Invalid Cursor Recovery
**What we're testing**: Backend gracefully handles stale/invalid cursors

**Test Steps**:
```bash
# Get cursor from page 1
# pagination.cursor = { "createdAt": 1711270700000, "postId": "post10" }

# Delete post10 from database
# Use cursor anyway
curl -X GET "http://localhost:8000/api/posts?feedType=global&limit=5&cursor=..." \
  -H "Authorization: Bearer <token>"

# Expected:
# - Backend logs: "Cursor post not found, starting from beginning"
# - Response: returns 5 posts starting from latest (no crash)
```

**Verify**:
- ✅ No 500 error (graceful recovery)
- ✅ Feed continues from beginning (not stuck)
- ✅ User sees posts (not blank feed)

---

## PERFORMANCE TARGETS

| Metric | Target | Acceptable | Critical |
|--------|--------|-----------|----------|
| First page latency | < 100ms | < 200ms | > 500ms ❌ |
| Subsequent pages | < 50ms | < 100ms | > 300ms ❌ |
| DB queries per request | 1 | 1 | > 1 ❌ (N+1) |
| Duplicate post rate | 0% | 0% | > 0% ❌ |
| hasMore accuracy | 100% | 100% | < 99% ❌ |

---

## REGRESSION TESTS (Comparing to Phase 2)

| Feature | Phase 2 | Phase 3 | Status |
|---------|---------|---------|--------|
| Cursor format | postId string | { createdAt, postId } | ✅ Upgraded |
| Cursor handling | Fake object ❌ | Real DocumentSnapshot | ✅ Fixed |
| URL overflow | Not handled | Detected + logged | ✅ Added |
| Tab contamination | BROKEN ❌ | Separated per feedType | ✅ Fixed |
| Pagination determinism | ✅ | ✅ | ✅ Maintained |
| hasMore accuracy | ✅ | ✅ | ✅ Maintained |

---

## GO/NO-GO DECISION

**All tests must PASS before proceeding to Phase 4.**

- [ ] TEST 1: Composite cursors generated correctly
- [ ] TEST 2: No duplicate posts across pages
- [ ] TEST 3: Deterministic ordering (tie-breaking works)
- [ ] TEST 4: URL overflow detected and handled
- [ ] TEST 5: Per-feed-type seenIds separation working
- [ ] TEST 6: hasMore flag accurate
- [ ] TEST 7: Invalid cursors recovered gracefully
- [ ] Performance: All metrics within target

**Status**: ⏳ READY FOR QA

---

## DEPLOYMENT CHECKLIST

Before going to production:

- [ ] All 7 tests pass in staging
- [ ] Performance metrics verified
- [ ] Cursor migration tested (old → new format)
- [ ] Rollback plan documented
- [ ] Monitoring alerts set up for 414 errors
- [ ] Client SDK updated to send new cursor format
- [ ] Database indices optimized (createdAt, __name__)

