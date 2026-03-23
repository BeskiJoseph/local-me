import 'dart:async';
import 'package:flutter/material.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/comment_service.dart';
import 'package:testpro/core/state/feed_controller.dart';
import 'package:testpro/core/state/feed_session.dart';
import 'package:testpro/core/events/feed_events.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/config/app_theme.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import 'package:testpro/screens/event_post_card.dart';
import 'package:testpro/screens/new_post_screen.dart';
import 'package:testpro/screens/post_reels_view.dart';
import 'package:testpro/utils/safe_error.dart';
import 'package:testpro/widgets/feed/feed_shimmer.dart';
import 'package:testpro/services/location_service.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/core/state/provider_container.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum FeedLayoutType { list, paged }

class PaginatedFeedList extends ConsumerStatefulWidget {
  final String feedType;
  final String? userCity;
  final String? userCountry;
  final FeedLayoutType layoutType;
  final String? mediaType;
  final List<Post> initialPosts;
  final int startIndex;
  final bool? initialHasMore;
  final Widget Function(BuildContext, Post, int, bool)? itemBuilder;

  const PaginatedFeedList({
    super.key,
    required this.feedType,
    this.userCity,
    this.userCountry,
    this.layoutType = FeedLayoutType.list,
    this.mediaType,
    this.initialPosts = const [],
    this.startIndex = 0,
    this.initialHasMore,
    this.itemBuilder,
  });

  @override
  ConsumerState<PaginatedFeedList> createState() => _PaginatedFeedListState();
}

class _PaginatedFeedListState extends ConsumerState<PaginatedFeedList>
    with AutomaticKeepAliveClientMixin {
  late final ScrollController _scrollController;
  late final PageController _pageController;
  final FeedController _feedController = FeedController();
  final Map<String, bool?> _likedPostIds = {};

  /// Local cache of hidden post IDs — survives feed refreshes within the session
  static final Set<String> _hiddenPosts = {};

  Timer? _debounce;
  Timer? _pollingTimer;
  StreamSubscription? _eventSubscription;
  DateTime _feedLoadedAt = DateTime.now();
  DateTime? _lastProactivePoll;
  late int _currentIndex;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint('📄 PaginatedFeedList Init: feedType=${widget.feedType}, initialHasMore=${widget.initialHasMore}');
    _scrollController = ScrollController();
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);

    if (widget.initialPosts.isNotEmpty) {
      _feedController.appendPosts(widget.initialPosts, refresh: true);
      
      // ✅ Issue 4: Only mark the current viewed post as seen, not the whole batch
      if (widget.startIndex < widget.initialPosts.length) {
        FeedSession.instance
            .markSeen([widget.initialPosts[widget.startIndex].id]);
      }

      if (widget.initialHasMore != null) {
        _feedController.hasMore = widget.initialHasMore!;
      }
    } else {
      _initializeFeed();
    }

    if (widget.layoutType == FeedLayoutType.list) {
      _scrollController.addListener(_onScroll);
    } else {
      _pageController.addListener(_onScroll);
    }

    _eventSubscription = FeedEventBus.events.listen(_handleFeedEvent);
    _startPolling();
  }

  Future<void> _initializeFeed() async {
    if (widget.feedType == 'local' && LocationService.currentPosition == null) {
      // Proactively detect location if first screen
      await LocationService.detectLocation();
    }
    _loadMorePosts(refresh: true);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkForNewPosts(),
    );
  }

  Future<void> _checkForNewPosts({bool isProactive = false}) async {
    // 🛡️ Cooldown for proactive polls to prevent spam (min 5s between requests)
    if (isProactive) {
      final now = DateTime.now();
      if (_lastProactivePoll != null &&
          now.difference(_lastProactivePoll!).inSeconds < 5) {
        return;
      }
      _lastProactivePoll = now;
      debugPrint('🚀 Proactive poll triggered (reached bottom)');
    }
    if (widget.feedType == 'local') {
      // Local: poll using geo coordinates
      final pos = await PostService.getCurrentPosition();
      if (pos == null) return;

      try {
        final response = await BackendService.getNewPostsSince(
          lat: (pos as dynamic).latitude,
          lng: (pos as dynamic).longitude,
          sinceTimestamp: _feedLoadedAt.millisecondsSinceEpoch - 10000,
          maxDistance: 10.0,
          watchedIds: FeedSession.instance.seenIdsParam,
          sid: FeedSession.instance.sessionId,
          mediaType: widget.mediaType,
        );

        if (response.success && response.data != null) {
          final List<dynamic> rawPosts = response.data!;
          if (rawPosts.isEmpty) return;
          final newPosts = rawPosts
              .map((json) => Post.fromJson(json as Map<String, dynamic>))
              .toList();
          FeedSession.instance.markSeen(newPosts.map((p) => p.id).toList());
          if (mounted) {
            // ✅ BACKGROUND POLL: Do not modify historical hasMore state
            _feedController.appendPosts(newPosts, isHistorical: false);
            _feedLoadedAt = DateTime.now();
          }
        }
      } catch (e) {
        debugPrint('Silent polling error: $e');
      }
    } else if (widget.feedType == 'city' && widget.userCity != null) {
      // ✅ City-level live polling
      try {
        final response = await BackendService.getNewPostsSince(
          city: widget.userCity,
          sinceTimestamp: _feedLoadedAt.millisecondsSinceEpoch - 10000,
          watchedIds: FeedSession.instance.seenIdsParam,
          sid: FeedSession.instance.sessionId,
        );
        if (response.success && response.data != null) {
          final List<dynamic> rawPosts = response.data!;
          if (rawPosts.isEmpty) return;
          final newPosts = rawPosts
              .map((json) => Post.fromJson(json as Map<String, dynamic>))
              .toList();
          FeedSession.instance.markSeen(newPosts.map((p) => p.id).toList());
          if (mounted) {
            // ✅ BACKGROUND POLL: Do not modify historical hasMore state
            _feedController.appendPosts(newPosts, isHistorical: false);
            _feedLoadedAt = DateTime.now();
          }
        }
      } catch (e) {
        debugPrint('Silent city polling error: $e');
      }
    } else {
      // Global feed poll
      try {
        final response = await PostService.getPostsPaginated(
          feedType: widget.feedType,
          limit: 5,
        );
        final newPosts = response.data
            .where(
              (p) =>
                  !_feedController.posts.any((existing) => existing.id == p.id),
            )
            .toList();
        if (newPosts.isNotEmpty && mounted) {
          final container = GlobalProviderContainer.instance;
          for (var p in newPosts) {
            container.read(postInteractionProvider.notifier).initializePost(p);
          }
          FeedSession.instance.markSeen(newPosts.map((p) => p.id).toList());
          // ✅ BACKGROUND POLL: Do not modify historical hasMore state
          _feedController.appendPosts(newPosts, isHistorical: false);
          _feedLoadedAt = DateTime.now();
        }
      } catch (e) {
        debugPrint('Silent global polling error: $e');
      }
    }
  }

  void _handleFeedEvent(FeedEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case FeedEventType.postCreated:
        if (event.data is Post) {
          // ✅ Append to bottom as per user request "not top at bottom"
          _feedController.appendPosts([event.data as Post]);
        } else if (event.data is String) {
          _fetchAndAppendNewPost(event.data as String);
        }
        break;
      case FeedEventType.postDeleted:
        final postId = event.data is String
            ? event.data as String
            : event.data.toString();
        _hiddenPosts.add(postId); // Cache so it stays hidden after refresh
        _feedController.deletePost(event.data);
        break;
      case FeedEventType.postLiked:
        final data = event.data as Map<String, dynamic>;
        _likedPostIds[data['postId']] = data['isLiked'];
        _feedController.updatePostLike(
          data['postId'],
          data['isLiked'],
          data['likeCount'],
        );
        break;
      case FeedEventType.commentAdded:
        final data = event.data as Map<String, dynamic>;
        _feedController.updatePostCommentCount(
          data['postId'],
          data['commentCount'],
        );
        break;
      case FeedEventType.postUpdated:
        final data = event.data as Map<String, dynamic>;
        _feedController.updatePost(data['postId'], data['updates']);
        break;
      default:
        break;
    }
  }

  Future<void> _fetchAndAppendNewPost(String postId) async {
    try {
      final response = await BackendService.getPost(postId);
      if (response.success && response.data != null) {
        final post = Post.fromJson(response.data!);
        // ✅ LIVE EVENT: Do not modify historical hasMore state
        _feedController.appendPosts([post], isHistorical: false);
      }
    } catch (e) {
      debugPrint('Error fetching new post: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pollingTimer?.cancel();
    _eventSubscription?.cancel();

    if (_scrollController.hasClients) {
      _scrollController.removeListener(_onScroll);
    }
    if (_pageController.hasClients) {
      _pageController.removeListener(_onScroll);
    }

    _scrollController.dispose();
    _pageController.dispose();
    _feedController.dispose();
    super.dispose();
  }

  void _onScroll() {
    bool isAtEnd = false;
    final posts =
        _feedController.posts; // Get posts here for paged layout calculation

    if (widget.layoutType == FeedLayoutType.list) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      isAtEnd = currentScroll >= maxScroll - 600; // Even earlier for List
    } else {
      if (!_pageController.hasClients) return;
      final currentPage = _pageController.page ?? 0.0;
      isAtEnd =
          currentPage >=
          (posts.length - 2.5); // Much earlier for Reels (2.5 indices from end)
    }

    if (isAtEnd) {
      if (_feedController.hasMore && !_feedController.isLoading) {
        debugPrint(
          '📜 Proactive load more [${widget.feedType}/${widget.layoutType}] triggered',
        );
        _loadMorePosts();
      } else if (!_feedController.hasMore && !_feedController.isLoading) {
        _checkForNewPosts(isProactive: true);
      }
    }
  }

  Future<void> _loadMorePosts({bool refresh = false}) async {
    // ✅ FIX 2: Only check for new posts (polling) if we are NOT in the middle of a pagination load
    // and if we have a reasonable amount of history to warrant idling.
    if (_feedController.isLoading) return;
    
    // If we have less than 20 items, ignore hasMore=false and keep trying to prime the feed
    if (!_feedController.hasMore && _feedController.posts.length < 20) {
       debugPrint('♻️ hasMore is false but list is short. Retrying load instead of polling.');
       _loadMorePosts();
       return;
    }

    if (!_feedController.hasMore) {
      return;
    }

    if (refresh) {
      _feedController.clear(notify: false);
      _likedPostIds.clear();
      // NOTE: We NO LONGER reset FeedSession here. 
      // This ensures that fresh queries still skip posts the user has already seen.
      _feedLoadedAt = DateTime.now(); // Reset polling anchor too
    }

    debugPrint('🚀 _loadMorePosts called: hasMore=${_feedController.hasMore}, isLoading=${_feedController.isLoading}');
    _feedController.setLoading(true);
    _feedController.setError(null);

    final isLocal = widget.feedType == 'local';

    try {
      final watchedParam = FeedSession.instance.seenIdsParam;

      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        // Local/global: rely on seenIds only; no distance cursors
        watchedIds: FeedSession.instance.seenIdsParam,
        limit: 10,
        mediaType: widget.mediaType,
      );

      final data = response.data;
      debugPrint('✅ Received ${data.length} posts from API (hasMore: ${response.hasMore})');
      
      // ✅ FIX 4: Removing bulk markSeen from API response. 
      // We ONLY mark as seen when the user actually VIEWS the item.
      // FeedSession.instance.markSeen(data.map((p) => p.id).toList());

        if (mounted) {
          final container = GlobalProviderContainer.instance;
          for (var p in data) {
            _likedPostIds[p.id] = p.isLiked;
            container.read(postInteractionProvider.notifier).initializePost(p);
          }

          // 🚀 PRELOAD TOP-3 COMMENTS for instant-feel UX
          if (refresh || _feedController.posts.isEmpty) {
            for (int i = 0; i < data.length && i < 3; i++) {
              ref.read(commentCacheProvider.notifier).preload(data[i].id);
            }
          }

          _feedController.appendPosts(
            data,
            refresh: refresh,
            hasMore: response.hasMore,
          );
          _feedLoadedAt =
              DateTime.now(); // ⚓ Fix: Update polling anchor to current refresh time
        }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) _feedController.setError(e.toString());
    } finally {
      if (mounted) _feedController.setLoading(false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadMorePosts(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ListenableBuilder(
      listenable: _feedController,
      builder: (context, _) {
        final posts = _feedController.posts;
        final isLoading = _feedController.isLoading;
        final error = _feedController.error;
        final hasMore = _feedController.hasMore;

        if (posts.isEmpty && isLoading) {
          return const FeedShimmer(itemCount: 3);
        }

        if (error != null && posts.isEmpty) {
          return _buildErrorState(error);
        }

        if (posts.isEmpty && !isLoading) {
          return _buildEmptyState(widget.feedType);
        }

        Widget mainContent;

        if (widget.layoutType == FeedLayoutType.paged) {
          mainContent = PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: posts.length + 1, // Always +1 for loader/footer trigger
            onPageChanged: (index) {
              if (mounted) {
                setState(() => _currentIndex = index);
                
                debugPrint('🎞️ Reel swiped to index: $index (total: ${posts.length}, hasMore: ${_feedController.hasMore}, loading: ${_feedController.isLoading})');

                // ✅ 1. Mark as seen when viewed (User's specific fix 🥇 1)
                if (index < posts.length) {
                  FeedSession.instance.markSeen([posts[index].id]);
                }

                // ✅ 2. Trigger fetch early (Issue 5: length - 3 for better UX)
                if (index >= posts.length - 3 &&
                    _feedController.hasMore &&
                    !_feedController.isLoading) {
                  debugPrint('🎞️ Reels fetchNext triggered at index $index');
                  _loadMorePosts();
                }
              }
            },
            itemBuilder: (context, index) {
              if (index >= posts.length) {
                return Center(
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Checking for new reels...",
                          style: TextStyle(color: Colors.white70),
                        ),
                );
              }
              final post = posts[index];
              if (widget.itemBuilder != null) {
                return widget.itemBuilder!(
                  context,
                  post,
                  index,
                  index == _currentIndex,
                );
              }
              return NextdoorStylePostCard(post: post, key: ValueKey(post.id));
            },
          );
        } else {
          mainContent = ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount:
                posts.length +
                1 +
                (widget.feedType == 'local' ? 1 : 0) +
                (_feedController.isCycling ? 1 : 0),
            itemBuilder: (context, index) {
              int adjustedIndex = index;

              // 1. Cycle Banner
              if (_feedController.isCycling && index == 0) {
                return _buildCyclingBanner();
              }
              if (_feedController.isCycling) adjustedIndex--;

              // 2. Local Header
              if (widget.feedType == 'local' && adjustedIndex == 0) {
                return const SizedBox.shrink(); // Placeholder if no banner exists
              }
              if (widget.feedType == 'local') adjustedIndex--;

              // 3. Footer / Loader
              if (adjustedIndex == posts.length) {
                if (error != null) return _buildRetryFooter();
                if (isLoading)
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                if (!hasMore) return _buildEndOfFeedFooter();
                return const SizedBox(height: 100);
              }

              // 4. Post
              if (adjustedIndex < 0 || adjustedIndex >= posts.length)
                return const SizedBox.shrink();
              final post = posts[adjustedIndex];

              if (_hiddenPosts.contains(post.id))
                return const SizedBox.shrink();

              // Special treatment for videos to open in Reels view with current cursors
              if (post.mediaType == 'video') {
                return NextdoorStylePostCard(
                  post: post,
                  key: ValueKey(post.id),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostReelsView(
                          posts: posts, // Pass current list
                          startIndex: adjustedIndex,
                          initialHasMore: _feedController.hasMore,
                        ),
                      ),
                    );
                  },
                );
              }

              // Special treatment for Events in the main feed
              if (post.isEvent || post.category.toLowerCase() == 'events') {
                return EventPostCard(
                  post: post,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostReelsView(
                        posts: posts,
                        startIndex: adjustedIndex,
                        feedType: widget.feedType,
                        userCity: widget.userCity,
                        userCountry: widget.userCountry,
                        initialHasMore: _feedController.hasMore,
                        isActiveTab: true,
                      ),
                    ),
                  ),
                );
              }

              if (widget.itemBuilder != null) {
                return widget.itemBuilder!(context, post, adjustedIndex, false);
              }
              return NextdoorStylePostCard(
                post: post,
                key: ValueKey(post.id),
                initialIsLiked: _likedPostIds[post.id],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostReelsView(
                      posts: posts,
                      startIndex: adjustedIndex,
                      feedType: widget.feedType,
                      userCity: widget.userCity,
                      userCountry: widget.userCountry,
                      initialHasMore: _feedController.hasMore,
                      isActiveTab: true,
                    ),
                  ),
                ),
              );
            },
          );
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: const Color(0xFF6C5CE7),
          child: mainContent,
        );
      },
    );
  }

  Widget _buildCyclingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.blue.withValues(alpha: 0.05),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.refresh, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'ve seen all nearby posts — showing from the beginning',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetryFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 20,
            color: Color(0xFF8A8A8A),
          ),
          const SizedBox(height: 8),
          const Text(
            'Unable to load more posts',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: Color(0xFF8A8A8A),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _loadMorePosts(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildEndOfFeedFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 32,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'You\'ve caught up with everything nearby',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Refreshing automatically in 30s',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: Color(0xFFE53935),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              safeErrorMessage(error, fallback: 'Failed to load posts.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _loadMorePosts(refresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String feedType) {
    final isLocal = feedType == 'local';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLocal ? Icons.near_me_rounded : Icons.public_rounded,
                size: 40,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isLocal ? 'No posts near you yet' : 'No global posts yet',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isLocal
                  ? 'Be the first to share something with your neighborhood!'
                  : 'Be the first to share something with the world!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NewPostScreen()),
                  );
                },
                icon: const Icon(Icons.edit_rounded, size: 20),
                label: const Text('Create Post'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
