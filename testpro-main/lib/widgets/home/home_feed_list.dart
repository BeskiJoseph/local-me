import 'package:flutter/material.dart';
import 'dart:async';
import 'package:testpro/services/post_service.dart';
import 'package:flutter/foundation.dart';
import 'package:testpro/utils/safe_error.dart';
import '../../models/post.dart';
import '../../models/paginated_response.dart';
import '../../config/app_theme.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/post_reels_view.dart';

/// Feed list — owns its ScrollController, caches the stream,
/// and uses AutomaticKeepAliveClientMixin to preserve scroll position.
class HomeFeedList extends StatefulWidget {
  final String feedType;
  final String? userCity;
  final String? userCountry;
  final bool isLoadingLocation;
  final String? locationError;
  final VoidCallback onRetryLocation;
  final String searchQuery;

  const HomeFeedList({
    super.key,
    required this.feedType,
    required this.userCity,
    required this.userCountry,
    required this.isLoadingLocation,
    required this.locationError,
    required this.onRetryLocation,
    required this.searchQuery,
  });

  @override
  State<HomeFeedList> createState() => _HomeFeedListState();

  /// 🔥 Static method to add new post to feed (called from new_post_screen)
  static void addNewPost(Post post) {
    debugPrint('➕ Adding new post to HomeFeedList: ${post.id}');
    _HomeFeedListState._tempPosts.insert(0, post);
    _HomeFeedListState._likedPostIds[post.id] = post.isLiked;
    // 🔥 Clear cached future to force FutureBuilder to rebuild
    _HomeFeedListState._feedFuture = null;
    // 🔥 Trigger rebuild
    _HomeFeedListState._triggerRebuild?.call();
  }
}

class _HomeFeedListState extends State<HomeFeedList>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  static final Map<String, bool?> _likedPostIds = {};
  
  // 🔥 Static callback to trigger rebuild from outside
  static VoidCallback? _triggerRebuild;

  static Future<PaginatedResponse<Post>>? _feedFuture;
  String? _futureFeedType;
  String? _futureCity;
  String? _futureCountry;

  // Static cache to persist posts across navigation
  static final Map<String, PaginatedResponse<Post>> _postsCache = {};

  // Static temporary posts to persist across widget recreation
  static final List<Post> _tempPosts = [];

  // Static set of deleted post IDs to persist optimistic removals
  static final Set<String> _deletedPostIds = {};

  @override
  bool get wantKeepAlive => true;

  String get _cacheKey =>
      '${widget.feedType}_${widget.userCity}_${widget.userCountry}';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    // 🔥 Set up rebuild callback for external post additions
    _triggerRebuild = () {
      if (mounted) {
        setState(() {});
        debugPrint('🔥 HomeFeedList rebuilt after new post added');
      }
    };
    
    // Restore from cache if available
    if (_postsCache.containsKey(_cacheKey)) {
      _feedFuture = Future.value(_postsCache[_cacheKey]);
      _futureFeedType = widget.feedType;
      _futureCity = widget.userCity;
      _futureCountry = widget.userCountry;
    }

  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _processPostCreated(Post postData) {
    debugPrint('➕ Post title: ${postData.title}');
    debugPrint('➕ Post author: ${postData.authorName}');
    debugPrint('➕ Post media URL: ${postData.mediaUrl}');
    debugPrint('➕ Post media type: ${postData.mediaType}');

    // Check if this is an update to an existing temporary post
    final existingIndex = _tempPosts.indexWhere((p) => p.id == postData.id);
    if (existingIndex != -1) {
      debugPrint(
        '🔄 Updating existing temporary post at index: $existingIndex',
      );
      // Replace the existing temporary post with updated version
      setState(() {
        _tempPosts[existingIndex] = postData;
      });
      debugPrint(
        '🔄 Temporary post updated with media URL: ${postData.mediaUrl != null}',
      );
    } else {
      debugPrint('➕ Adding new temporary post to feed: ${postData.id}');
      // Add new temporary post to the top of the feed
      setState(() {
        _likedPostIds[postData.id] = postData.isLiked;
        _tempPosts.insert(0, postData);
      });
    }
    debugPrint(
      '➕ Temporary post processed. Current count: ${_tempPosts.length}',
    );
    debugPrint('➕ Temp posts IDs: ${_tempPosts.map((p) => p.id).toList()}');
  }

  Future<PaginatedResponse<Post>> _getFuture() {
    final paramsChanged =
        _futureFeedType != widget.feedType ||
        _futureCity != widget.userCity ||
        _futureCountry != widget.userCountry;

    if (_feedFuture == null || paramsChanged) {
      debugPrint('📥 Fetching fresh posts for: ${widget.feedType}');
      _futureFeedType = widget.feedType;
      _futureCity = widget.userCity;
      _futureCountry = widget.userCountry;
      _feedFuture =
          PostService.getPostsPaginated(
            feedType: widget.feedType,
            userCity: widget.userCity,
            userCountry: widget.userCountry,
            limit: 20, // Initial load limit
          ).then((response) {
            // Populate liked posts map
            for (var p in response.data) {
              _likedPostIds[p.id] = p.isLiked;
            }

            return response;
          });
    } else {
      debugPrint('📥 Using existing future for: ${widget.feedType}');
    }
    return _feedFuture!;
  }

  /// Public method to force feed refresh (called after post creation)
  Future<PaginatedResponse<Post>> refreshFeed() {
    debugPrint('🔄 Refreshing feed: $_cacheKey');
    _postsCache.remove(_cacheKey); // Clear cache
    // FeedSession.instance.reset(); // Clear session deduplication on manual refresh
    setState(() {
      _HomeFeedListState._feedFuture = null;
      // Don't clear temporary posts here - they should persist until real post arrives
      debugPrint('🔄 Feed future reset, will fetch fresh data');
      debugPrint(
        '🔄 Temp posts preserved during refresh: ${_tempPosts.length}',
      );
    });
    return _getFuture();
  }

  /// Static method to clear all temporary posts
  static void clearAllTempPosts() {
    debugPrint('🧹 Clearing all temporary posts');
    _tempPosts.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoadingLocation) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (widget.locationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                widget.locationError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onRetryLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Global feed doesn't need location for trending algorithm
    if (widget.feedType == 'local' && widget.userCity == null) {
      return const Center(child: Text('Waiting for location...'));
    }

    // 🔥 CRITICAL FIX: Show loading immediately when no cached data and future is being created
    // This prevents "No posts" flash before spinner appears
    final isInitiallyLoading = _feedFuture == null && !_postsCache.containsKey(_cacheKey);
    if (isInitiallyLoading) {
      // Trigger the future creation but show spinner immediately
      _getFuture();
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return FutureBuilder<PaginatedResponse<Post>>(
      future: _getFuture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _feedFuture != null &&
            !_postsCache.containsKey(_cacheKey)) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        if (snapshot.hasError && !_postsCache.containsKey(_cacheKey)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                safeErrorMessage(
                  snapshot.error,
                  fallback: 'Failed to load feed.',
                ),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        // Cache successful response
        if (snapshot.hasData && snapshot.data != null) {
          _postsCache[_cacheKey] = snapshot.data!;
        }

        final response = snapshot.data ?? _postsCache[_cacheKey];
        final posts = response?.data ?? [];

        // Clear temporary posts when we get fresh posts from server
        // This happens when _feedFuture is null and we're fetching fresh data
        if (_feedFuture == null &&
            posts.isNotEmpty &&
            _tempPosts.isNotEmpty &&
            snapshot.connectionState == ConnectionState.done) {
          // Check if these are actually new posts (not from cache)
          final isFreshData =
              response != null && response != _postsCache[_cacheKey];
          if (isFreshData) {
            debugPrint(
              '🔄 Fresh posts from server (${posts.length}), clearing temporary posts (${_tempPosts.length})',
            );
            _tempPosts.clear();
          }
        }

        // Combine temporary posts with real posts
        // 🔥 Remove duplicates: skip server posts that already exist in temp posts
        final tempPostIds = _tempPosts.map((p) => p.id).toSet();
        final uniqueServerPosts = posts.where((p) => !tempPostIds.contains(p.id)).toList();
        final allPosts = [..._tempPosts, ...uniqueServerPosts];

        // Apply optimistic deletion filter (tombstones)
        allPosts.removeWhere((p) => _deletedPostIds.contains(p.id));
        if (kDebugMode) {
          debugPrint('📊 Building feed display:');
          debugPrint('📊  - Temp posts: ${_tempPosts.length}');
          debugPrint('📊  - Real posts: ${posts.length}');
          debugPrint('📊  - Total posts: ${allPosts.length}');
          if (_tempPosts.isNotEmpty) {
            debugPrint(
              '📊  - Temp post IDs: ${_tempPosts.map((p) => p.id).toList()}',
            );
          }
        }

        final filteredPosts = widget.searchQuery.isEmpty
            ? allPosts.where((post) {
                // Hide archived events from the feed entirely
                if (post.isEvent && post.computedStatus == 'archived')
                  return false;
                return true;
              }).toList()
            : allPosts.where((post) {
                // Hide archived events from the feed entirely
                if (post.isEvent && post.computedStatus == 'archived')
                  return false;
                final q = widget.searchQuery.toLowerCase();
                return post.title.toLowerCase().contains(q) ||
                    post.body.toLowerCase().contains(q) ||
                    post.authorName.toLowerCase().contains(q) ||
                    post.category.toLowerCase().contains(q);
              }).toList();

        // 🔥 CRITICAL FIX: Don't show "No posts" while still loading
        final isStillLoading = snapshot.connectionState == ConnectionState.waiting || 
                               snapshot.connectionState == ConnectionState.active;
        
        if (filteredPosts.isEmpty && !isStillLoading) {
          return RefreshIndicator(
            onRefresh: refreshFeed,
            color: AppTheme.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.searchQuery.isEmpty
                              ? 'No posts yet in this area'
                              : 'No posts found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (widget.searchQuery.isEmpty &&
                            widget.userCity != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${widget.userCity}, ${widget.userCountry}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // 🔥 Show loading spinner if filteredPosts is empty but still loading
        if (filteredPosts.isEmpty && isStillLoading) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          );
        }

        return RefreshIndicator(
          onRefresh: refreshFeed,
          color: AppTheme.primary,
          child: ListView.separated(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // Removed "Create Post" bar from top of feed
            padding: const EdgeInsets.only(top: 0, bottom: 100),
            itemCount: filteredPosts.length,
            separatorBuilder: (context, index) => Container(
              height: 10,
              color: const Color(0xFFF2F2F2), // slightly lighter thick gray
            ),
            itemBuilder: (context, index) {
              final post = filteredPosts[index];
              // Route to EventPostCard if isEvent OR category is Events
              if (post.isEvent || post.category.toLowerCase() == 'events') {
                return EventPostCard(post: post);
              }
              return NextdoorStylePostCard(
                post: post,
                currentCity: widget.userCity,
                initialIsLiked: _likedPostIds[post.id],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostReelsView(
                        posts: filteredPosts,
                        startIndex: index,
                        feedType: widget.feedType,
                        initialHasMore: response?.hasMore ?? false,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// "Create Post..." bar — REMOVED from feed as per request
// Use bottom nav Create button instead
// ─────────────────────────────────────────────────────────────
