import 'package:flutter/material.dart';
import 'dart:async';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/core/events/feed_events.dart';
import 'package:testpro/core/state/feed_controller.dart';
import 'package:testpro/core/state/feed_session.dart';
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
}

class _HomeFeedListState extends State<HomeFeedList>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  StreamSubscription<FeedEvent>? _eventSubscription;
  static final Map<String, bool?> _likedPostIds = {};

  Future<PaginatedResponse<Post>>? _feedFuture;
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
    // Restore from cache if available
    if (_postsCache.containsKey(_cacheKey)) {
      _feedFuture = Future.value(_postsCache[_cacheKey]);
      _futureFeedType = widget.feedType;
      _futureCity = widget.userCity;
      _futureCountry = widget.userCountry;
    }

    // Listen for post creation and deletion events for optimistic updates
    _eventSubscription = FeedEventBus.events.listen((event) {
      debugPrint('📬 HomeFeedList received event: ${event.type}');
      if (!mounted) {
        debugPrint('⚠️ HomeFeedList not mounted, skipping event');
        return;
      }
      if (event.type == FeedEventType.postCreated) {
        debugPrint('📬 Post created event received');
        final postData = event.data;
        if (postData is Post) {
          debugPrint('➕ Processing post: ${postData.id}');
          _processPostCreated(postData);
        } else if (postData is String) {
          debugPrint('➕ Processing postId: $postData');
          // Fetch the full post object if only ID was emitted
          BackendService.getPost(postData).then((response) {
            if (response.success && response.data != null && mounted) {
              final post = Post.fromJson(response.data!);
              _processPostCreated(post);
            }
          });
        } else {
          debugPrint(
            '⚠️ Event data is not a Post or String: ${postData.runtimeType}',
          );
        }
      } else if (event.type == FeedEventType.postDeleted) {
        debugPrint('📬 Post deleted event received');
        final postId = event.data;
        if (postId is String) {
          debugPrint('➖ Removing temporary post: $postId');
          // Remove temporary post
          setState(() {
            _tempPosts.removeWhere((p) => p.id == postId);
            _deletedPostIds.add(postId);
          });
          debugPrint(
            '➖ Temporary post removed and tombstoned. Current count: ${_tempPosts.length}',
          );
        }
      } else if (event.type == FeedEventType.postLiked) {
        debugPrint('📬 Post liked event received');
        final data = event.data as Map<String, dynamic>;
        final String postId = data['postId'];
        final bool? isLiked = data['isLiked'];
        final int likeCount = data['likeCount'];

        if (mounted) {
          setState(() {
            if (isLiked != null) {
              _likedPostIds[postId] = isLiked;
            }

            // Update the count in the cache as well so it doesn't revert on rebuild
            for (var cacheKey in _postsCache.keys) {
              final cachedResponse = _postsCache[cacheKey]!;
              final posts = cachedResponse.data;
              final index = posts.indexWhere((p) => p.id == postId);
              if (index != -1) {
                posts[index] = posts[index].copyWith(
                  isLiked: isLiked ?? posts[index].isLiked,
                  likeCount: likeCount,
                );
              }
            }

            // Also update temporary posts
            final tempIndex = _tempPosts.indexWhere((p) => p.id == postId);
            if (tempIndex != -1) {
              _tempPosts[tempIndex] = _tempPosts[tempIndex].copyWith(
                isLiked: isLiked ?? _tempPosts[tempIndex].isLiked,
                likeCount: likeCount,
              );
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _eventSubscription?.cancel();
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
            watchedIds: FeedSession.instance.seenIdsParam(widget.feedType),
            limit: 20, // Initial load limit
          ).then((response) {
            // Track seen posts for cross-feed deduplication
            FeedSession.instance.markSeen(
              response.data.map((p) => p.id).toList(),
              feedType: widget.feedType,
            );

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
      _feedFuture = null;
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
        final allPosts = [..._tempPosts, ...posts];

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

        if (filteredPosts.isEmpty) {
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
