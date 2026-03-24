# Phase 4: Monitoring & Alerting Guide

**Real-time monitoring for hybrid feed ranking engine**

---

## Overview

After deploying Phase 4 (hybrid feed + ranking), monitor these 5 key metrics to ensure the system is working correctly.

---

## Metric 1: Response Time

**What**: How long hybrid feed requests take

**Where to track**: 
- Cloud Logging / DataDog / Prometheus
- Filter: `endpoint=/api/posts AND feedType=hybrid`

**Thresholds**:
```
🟢 Green (Normal):    100-300ms
🟡 Yellow (Slow):     300-500ms
🔴 Red (Too Slow):    > 500ms
```

**What it means**:
- **Green**: Normal. Merge + ranking working efficiently.
- **Yellow**: Investigate. Possible Firestore slow queries or large rankings.
- **Red**: Action needed. Geo-queries too expensive or ranking broken.

**Query (example - CloudLogging)**:
```sql
SELECT 
  TIMESTAMP_TRUNC(timestamp, MINUTE) as minute,
  COUNT(*) as requests,
  APPROX_QUANTILES(latency, 100)[OFFSET(50)] as p50_latency,
  APPROX_QUANTILES(latency, 100)[OFFSET(95)] as p95_latency,
  APPROX_QUANTILES(latency, 100)[OFFSET(99)] as p99_latency
FROM logs
WHERE jsonPayload.feedType = 'hybrid'
GROUP BY minute
ORDER BY minute DESC
```

---

## Metric 2: Error Rate

**What**: Percentage of hybrid feed requests that fail

**Where to track**: 
- Error logging / APM tool
- Filter: `endpoint=/api/posts AND feedType=hybrid AND status >= 500`

**Thresholds**:
```
🟢 Green:  < 0.1%
🟡 Yellow: 0.1% - 0.5%
🔴 Red:    > 0.5%
```

**What it means**:
- **Green**: Normal. Expected occasional errors from data issues.
- **Yellow**: Some requests failing. Check Firestore / database health.
- **Red**: Many failures. Likely data access layer broken.

**Alert**:
```
IF error_rate > 0.5% FOR 5 MINUTES THEN
  Send Slack alert: "Hybrid feed error rate critical"
  Page on-call engineer
```

**Common Errors**:
```
Firestore quota exceeded
  → Reduce batch size or add caching

Invalid coordinates
  → Client sending bad lat/lng (not our problem)

Cursor resolution failed
  → Post was deleted (graceful fallback used)

Distance calculation error
  → Latitude/longitude missing on posts
```

---

## Metric 3: Deduplication Efficiency

**What**: Are we successfully removing duplicates across pages?

**Where to track**:
- Custom logging in FeedService
- Already logged in `pagination.mergeInfo`

**How to calculate**:
```javascript
// From response
const dedup_efficiency = 100 * (merged - dedup) / merged;

// Example:
// merged = 80, deduped = 78
// efficiency = 100 * (80 - 78) / 80 = 2.5% duplicates removed

// Expected: 0-5% duplicates (most posts are unique)
```

**Thresholds**:
```
🟢 Green:  < 5% duplicates (healthy)
🟡 Yellow: 5% - 15% duplicates (cache issue?)
🔴 Red:    > 15% duplicates (seenIds not tracking correctly)
```

**What it means**:
- **Green**: Normal. Local + global sets have minimal overlap.
- **Yellow**: Too much overlap. Maybe same posts appearing in both sources.
- **Red**: Dedup logic broken. Session seenIds not being passed correctly.

**Query (CloudLogging)**:
```sql
SELECT 
  TIMESTAMP_TRUNC(timestamp, MINUTE) as minute,
  AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.mergedTotal'
  ) AS INT64)) as avg_merged,
  AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.dedupedTotal'
  ) AS INT64)) as avg_deduped,
  100 * (1 - AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.dedupedTotal'
  ) AS INT64)) / AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.mergedTotal'
  ) AS INT64))) as dedup_rate_percent
FROM logs
WHERE jsonPayload.feedType = 'hybrid'
GROUP BY minute
```

---

## Metric 4: Ranking Score Distribution

**What**: Are ranking scores varied and meaningful?

**Where to track**:
- Application Insights / Custom Dashboard
- Parse score field from response data

**Thresholds**:
```
🟢 Green:  Score range 0.2-0.9, variance > 0.1
🟡 Yellow: Score range 0.3-0.8, variance low
🔴 Red:    All scores 0.3-0.4 (frozen) or all 0.1 (broken)
```

**What it means**:
- **Green**: Normal. Posts ranked differently based on recency/engagement/distance.
- **Yellow**: Low variance. Maybe all posts similar age/engagement.
- **Red**: Ranking broken. Check if distance calculation or engagement scoring failing.

**Debug Query** (sample 100 posts):
```javascript
// Add to logging
const scores = data.map(p => p.score);
logger.info({
  avgScore: (scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(3),
  minScore: Math.min(...scores).toFixed(3),
  maxScore: Math.max(...scores).toFixed(3),
  stdDev: calculateStdDev(scores).toFixed(3)
});

// Expected output:
// avgScore: 0.650
// minScore: 0.120
// maxScore: 0.945
// stdDev: 0.210
```

**Alert**:
```
IF avg_score_variance < 0.05 FOR 10 MINUTES THEN
  Send Slack: "Ranking scores not varying - check distance calc"
```

---

## Metric 5: Feed Mix Quality (Local vs Global)

**What**: Is the local/global split healthy?

**Where to track**:
- Dashboard showing `mergeInfo.localPosts` vs `mergeInfo.globalPosts`
- Already in every response

**Thresholds**:
```
Expected for geo-search (depends on density):
- Dense city (SF, NYC):      60% local, 40% global
- Suburban area:             40% local, 60% global  
- Rural area:                20% local, 80% global

Alert if persistent skew:
- > 90% local (geo-queries broken?)
- < 10% local (local query returning nothing?)
```

**What it means**:
- **Balanced**: Normal. Local content prioritized, global fills gaps.
- **Too local**: Local area is very active (good).
- **Too global**: User in low-activity area (expected).
- **Broken**: Either local or global query failing.

**Query (CloudLogging)**:
```sql
SELECT 
  TIMESTAMP_TRUNC(timestamp, MINUTE) as minute,
  AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.localPosts'
  ) AS INT64)) as avg_local,
  AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.globalPosts'
  ) AS INT64)) as avg_global,
  100 * AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.localPosts'
  ) AS INT64)) / (AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.localPosts'
  ) AS INT64)) + AVG(CAST(json_extract_scalar(
    jsonPayload.mergeInfo, '$.globalPosts'
  ) AS INT64))) as local_percent
FROM logs
WHERE jsonPayload.feedType = 'hybrid'
GROUP BY minute
```

---

## Dashboard Setup (Example)

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4: HYBRID FEED MONITORING DASHBOARD                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Response Time (p95)        Error Rate              Requests/min │
│  ┌──────────────┐            ┌──────────┐           ┌──────────┐ │
│  │   245ms      │            │  0.02%   │           │  1250    │ │
│  │   🟢 Normal  │            │  🟢 Good │           │  📈↑5%   │ │
│  └──────────────┘            └──────────┘           └──────────┘ │
│                                                                   │
│  Dedup Efficiency           Score Variance         Local vs Global│
│  ┌──────────────┐            ┌──────────┐           ┌──────────┐ │
│  │  3.2% dups   │            │  0.198   │           │  52%/48% │ │
│  │  🟢 Healthy  │            │  🟢 Good │           │  🟢 Bal. │ │
│  └──────────────┘            └──────────┘           └──────────┘ │
│                                                                   │
│  Response Time Over Time (Last 24h)                              │
│  │                                                                │
│  │  300ms ┤      ╭─╮                                              │
│  │  200ms ┤  ╭───╯ ╰─╮       ╭──╮                               │
│  │  100ms ┤  │       ╰───────╯  ╰──╮                             │
│  │    0ms ┤──┴─────────────────────┘                             │
│  └────────┴──────────────────────────────────────────             │
│                                                                   │
│  Top Errors (Last 1h)                                            │
│  │ Firestore quota exceeded: 3 errors                            │
│  │ Invalid coordinates: 1 error                                  │
│  │ Cursor resolution failed: 5 errors                            │
│  └────────────────────────────────────────────────                │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Alert Configuration

### Priority 1 (Critical - Page On-Call)
```
IF error_rate > 1% FOR 5 MINUTES THEN alert P1
IF p95_latency > 1000ms FOR 10 MINUTES THEN alert P1
IF dedup_rate > 20% FOR 10 MINUTES THEN alert P1
```

### Priority 2 (High - Notify Team)
```
IF error_rate > 0.5% FOR 10 MINUTES THEN alert P2
IF p95_latency > 500ms FOR 15 MINUTES THEN alert P2
IF local_percent < 10% OR local_percent > 95% FOR 20 MINUTES THEN alert P2
```

### Priority 3 (Medium - Log for Review)
```
IF p95_latency > 300ms FOR 30 MINUTES THEN log P3
IF score_variance < 0.05 FOR 30 MINUTES THEN log P3
IF avg_score < 0.3 FOR 30 MINUTES THEN log P3
```

---

## Health Check Endpoints (Optional)

Add a health endpoint to help with monitoring:

```javascript
// GET /api/health/hybrid-feed
app.get('/api/health/hybrid-feed', async (req, res) => {
  try {
    // Test local query
    const localStart = Date.now();
    const localResult = await feedService.getLocalFeed({
      latitude: 37.7749,
      longitude: -122.4194,
      pageSize: 10
    });
    const localTime = Date.now() - localStart;
    
    // Test global query
    const globalStart = Date.now();
    const globalResult = await feedService.getGlobalFeed({
      pageSize: 10
    });
    const globalTime = Date.now() - globalStart;
    
    // Test ranking
    const rankingStart = Date.now();
    const testScore = feedService.computeScore(localResult.posts[0], {
      latitude: 37.7749,
      longitude: -122.4194
    });
    const rankingTime = Date.now() - rankingStart;
    
    res.json({
      status: 'healthy',
      tests: {
        localQuery: {
          time: localTime,
          status: localTime < 200 ? 'pass' : 'slow'
        },
        globalQuery: {
          time: globalTime,
          status: globalTime < 200 ? 'pass' : 'slow'
        },
        ranking: {
          time: rankingTime,
          score: testScore,
          status: rankingTime < 50 ? 'pass' : 'slow'
        }
      }
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});
```

---

## Incident Response

### If response time suddenly increases:

1. **Check Firestore quota**: `gcloud firestore describe` (Cloud Console)
   - Solution: Wait for quota reset (24h cycle)

2. **Check database connection**: Are queries slow?
   - Solution: Check Firestore Cloud Trace

3. **Check ranking computation**: Increase payload?
   - Solution: Reduce pageSize or batch size

### If error rate spikes:

1. **Check Firestore status**: Is it having issues?
   - Solution: Wait or contact Google Cloud Support

2. **Check network**: Are requests timing out?
   - Solution: Increase timeout or retry logic

3. **Check logs**: What errors are being returned?
   - Solution: Fix specific error type

### If duplicates appear:

1. **Check session tracking**: Is `seenPostIds` being passed?
   - Solution: Verify client sends `sid` parameter

2. **Check cursor logic**: Is cursor resolution working?
   - Solution: Verify cursor is base64 encoded/decoded correctly

3. **Check dedup logic**: Is it actually running?
   - Solution: Add debug logging to `deduplicatePosts()`

---

## Gradual Rollout Monitoring

If using feature flag to gradually enable hybrid feed:

```javascript
// Track: Who gets hybrid?
analytics.track('feed_assignment', {
  userId: user.id,
  feedType: Math.random() < 0.1 ? 'hybrid' : 'global',  // 10% hybrid
  variant: 'phase4_rollout'
});

// Compare metrics between groups
SELECT 
  feedType,
  COUNT(*) as users,
  AVG(timeOnFeed) as avg_time,
  AVG(likesPerSession) as avg_likes,
  AVG(sessionDuration) as avg_session
FROM user_sessions
WHERE date >= CURRENT_DATE() - 7
GROUP BY feedType
```

Expected after 1 week:
- Hybrid users should have equal or better engagement
- Response times should be acceptable
- Error rates similar to existing feeds

---

## Success Criteria

✅ Phase 4 considered **stable** when:
1. Error rate < 0.1% for 7 days
2. P95 latency < 300ms consistently
3. Dedup rate < 5%
4. Score distribution healthy (variance > 0.1)
5. Local/global mix expected for geography
6. No critical incidents

✅ Ready for **full rollout** when:
1. All metrics healthy for 2+ weeks
2. User engagement metrics positive (A/B test shows improvement)
3. Team confident in system
4. Runbook created and team trained

---

## Dashboard Tools Recommended

- **Cloud Logging**: Query Firestore logs
- **DataDog/New Relic**: Application Performance Monitoring
- **Prometheus + Grafana**: Custom metrics
- **Google Cloud Console**: Firestore metrics
- **Slack**: Alert notifications

---

**Monitor continuously for 2 weeks after launch. Adjust as needed.** 📊
