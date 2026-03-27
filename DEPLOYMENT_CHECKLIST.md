# Deployment Checklist - Feed UI Fixes

## Pre-Deployment Verification

### Code Review
- [ ] Backend changes in `feedService.js` compile without errors
- [ ] Backend changes in `postController.js` compile without errors
- [ ] Flutter changes in `post_state.dart` compile without errors
- [ ] Flutter changes in `paginated_feed_list.dart` compile without errors
- [ ] No breaking changes to existing APIs
- [ ] No breaking changes to existing state structure

### Testing Locally
- [ ] Local feed loads 15 posts on first load
- [ ] Global feed loads 15 posts on first load
- [ ] Scrolling local feed loads more posts (different IDs)
- [ ] Scrolling global feed loads more posts (different IDs)
- [ ] Switching between tabs shows correct posts
- [ ] Going back to a tab shows same posts as before (not reset)
- [ ] No "No posts found" message when posts should be visible
- [ ] Logs show correct feed type tracking
- [ ] Logs show dual cursor structure

### Edge Cases
- [ ] Empty local area (should show global fallback)
- [ ] No internet (should show cached posts)
- [ ] Rapid tab switching (should handle correctly)
- [ ] Rapid scrolling (should not duplicate posts)
- [ ] Long session (100+ posts loaded)

---

## Deployment Steps

### Backend Deployment
1. [ ] Backup current production code
2. [ ] Deploy `feedService.js` changes
3. [ ] Deploy `postController.js` changes
4. [ ] Verify server restarts without errors
5. [ ] Check backend logs for expected output
6. [ ] Run backend test suite (if available)

### Frontend Deployment
1. [ ] Backup current Flutter app version
2. [ ] Update `post_state.dart` code
3. [ ] Update `paginated_feed_list.dart` code
4. [ ] Run `flutter clean && flutter pub get`
5. [ ] Build APK/iOS build: `flutter build apk --release`
6. [ ] Test built app locally on device
7. [ ] Upload to TestFlight/Google Play Beta
8. [ ] Monitor crash reports (should be 0 new crashes)

---

## Post-Deployment Monitoring

### First Hour
- [ ] Monitor backend error logs
- [ ] Check error tracking (Sentry/similar)
- [ ] Monitor API response times
- [ ] Check database query performance

### First Day
- [ ] Monitor user session length
- [ ] Check for pagination-related errors
- [ ] Verify feed loads consistently
- [ ] Check duplicate post reports (should drop)

### First Week
- [ ] User feedback (should be positive)
- [ ] Feed load times (should be same or better)
- [ ] Error rates (should be lower)
- [ ] User retention (should be same or higher)

---

## Rollback Plan

If issues are found:

### Immediate Rollback
1. [ ] Identify the problem from logs
2. [ ] Revert backend to previous version
3. [ ] Revert Flutter app to previous version
4. [ ] Verify functionality restored
5. [ ] Post-mortem on what went wrong

### Root Cause Analysis
- [ ] Check logs from failed deployment
- [ ] Identify specific breaking change
- [ ] Write test to prevent regression
- [ ] Fix the issue
- [ ] Re-deploy with fix

---

## Success Criteria

✅ **All of these must be true after deployment:**

- [ ] No increase in backend error rates
- [ ] No increase in crash reports
- [ ] Feed loads consistently for all users
- [ ] No duplicate posts on any page
- [ ] Pagination advances correctly
- [ ] Local and Global feeds are separate
- [ ] Switching tabs works smoothly
- [ ] App performance is same or better
- [ ] Logs show expected output
- [ ] Users report improved experience

---

## Documentation

- [ ] README updated with new architecture
- [ ] API docs updated with dual cursor format
- [ ] Deployment guide updated
- [ ] Troubleshooting guide updated
- [ ] Team trained on new changes

---

## Sign-Off

- Backend Lead: ________________  Date: ______
- Frontend Lead: ________________  Date: ______
- QA Lead: ________________  Date: ______
- Product Lead: ________________  Date: ______

---

**Deployment Ready:** [ ] YES  [ ] NO

If NO, list blockers:
1. 
2. 
3. 

---

**Deployment Date:** ________________
**Deployment By:** ________________
**Verified By:** ________________

