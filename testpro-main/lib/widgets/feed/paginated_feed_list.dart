import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../services/backend_service.dart';
import '../../core/state/feed_controller.dart';
import '../../core/state/feed_session.dart';
import '../../models/post.dart';
import '../../config/app_theme.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/new_post_screen.dart';
import '../../screens/post_reels_view.dart';
import '../../utils/safe_error.dart';
import 'feed_shimmer.dart';

class PaginatedFeedList extends StatefulWidget {
  final String feedType;
  final String? userCity;
  final String? userCountry;

  const PaginatedFeedList({
    super.key,
    required this.feedType,
    this.userCity,
    this.userCountry,
  });

  @override
  State<PaginatedFeedList> createState() => _PaginatedFeedListState();
}

class _PaginatedFeedListState extends State<PaginatedFeedList> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final FeedController _feedController = FeedController();
  final Map<String, bool?> _likedPostIds = {};
  
  /// Local cache of hidden post IDs — survives feed refreshes within the session
  static final Set<String> _hiddenPosts = {};
  
  Timer? _debounce;
  Timer? _pollingTimer;
  StreamSubscription? _eventSubscription;
  DateTime _feedLoadedAt = DateTime.now();
  int _newPostsCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMorePosts();
    _scrollController.addListener(_onScroll);
    _eventSubscription = PostService.events.listen(_handleFeedEvent);
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkForNewPosts());
  }

  Future<void> _checkForNewPosts() async {
    if (widget.feedType != 'local') return;
    final pos = await PostService.getCurrentPosition();
    if (pos == null) return;

    try {
      final response = await BackendService.getNewPostsSince(
        lat: pos.latitude,
        lng: pos.longitude,
        sinceTimestamp: _feedLoadedAt.millisecondsSinceEpoch,
        maxDistance: _feedController.lastDistance > 0 ? _feedController.lastDistance : null,
      );

      if (response.success && response.data != null) {
        final List<dynamic> rawPosts = response.data!;
        if (rawPosts.isEmpty) return;

        final newPosts = rawPosts.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
        
        // Mark as seen in session
        FeedSession.instance.markSeen(newPosts.map((p) => p.id).toList());
        
        if (mounted) {
          setState(() {
            _newPostsCount += newPosts.length;
            _feedController.injectNewPosts(newPosts);
            _feedLoadedAt = DateTime.now();
          });
        }
      }
    } catch (e) {
      debugPrint('Silent polling error: $e');
    }
  }

  void _handleFeedEvent(FeedEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case FeedEventType.postCreated:
        if (event.data is String) {
          _fetchAndPrependNewPost(event.data as String);
        }
        break;
      case FeedEventType.postDeleted:
        final postId = event.data is String ? event.data as String : event.data.toString();
        _hiddenPosts.add(postId); // Cache so it stays hidden after refresh
        _feedController.deletePost(event.data);
        break;
      case FeedEventType.postLiked:
        final data = event.data as Map<String, dynamic>;
        _likedPostIds[data['postId']] = data['isLiked'];
        _feedController.updatePostLike(data['postId'], data['isLiked'], data['likeCount']);
        break;
      default:
        break;
    }
  }
  
  Future<void> _fetchAndPrependNewPost(String postId) async {
    try {
      final response = await BackendService.getPost(postId);
      if (response.success && response.data != null) {
        final post = Post.fromJson(response.data!);
        _feedController.prependPost(post);
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
    _scrollController.dispose();
    _feedController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) return;

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_feedController.isLoading &&
          _feedController.hasMore &&
          _feedController.error == null) {
        _loadMorePosts();
      }
    });
  }

  Future<void> _loadMorePosts({bool refresh = false}) async {
    if (_feedController.isLoading) return;
    if (!refresh && !_feedController.hasMore) return;

    if (refresh) {
      _feedController.clear(notify: false);
      _likedPostIds.clear();
      _feedController.setLoading(true);
      FeedSession.instance.reset(); // Clear session deduplication on manual refresh
    } else {
      _feedController.setLoading(true);
      _feedController.setError(null);
    }

    final isLocal = widget.feedType == 'local';

    try {
      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        // For global feed, use afterId. For local, use distance cursors.
        afterId: isLocal ? null : _feedController.cursor,
        lastDistance: isLocal ? _feedController.lastDistance : null,
        lastPostId: isLocal ? _feedController.lastPostId : null,
        watchedIds: FeedSession.instance.seenIdsParam,
        limit: 10,
      );

      final data = response.data;
      // Update shared cross-feed session
      FeedSession.instance.markSeen(data.map((p) => p.id).toList());

      if (mounted) {
        for (var p in data) {
          _likedPostIds[p.id] = p.isLiked;
        }
        _feedController.appendPosts(
          data, 
          refresh: refresh, 
          nextCursor: response.nextCursor,
          newLastDistance: response.lastDistance,
          newLastPostId: response.lastPostId,
          fallbackLevel: response.fallbackLevel,
        );
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

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _onRefresh,
              color: const Color(0xFF6C5CE7),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                itemCount: posts.length + (hasMore || error != null ? 1 : 0) + (_feedController.isCycling ? 1 : 0),
                itemBuilder: (context, index) {
                  // Cycle Banner at position 0
                  if (_feedController.isCycling && index == 0) {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.blue.withValues(alpha: 0.05),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.refresh, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'You\'ve seen all nearby posts — showing from the beginning',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Adjust index if cycling banner is shown
                  final adjustedIndex = _feedController.isCycling ? index - 1 : index;

                  if (adjustedIndex == posts.length) {
                    if (error != null) {
                      return _buildRetryFooter();
                    }
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  
                  // Defensive check
                  if (adjustedIndex < 0 || adjustedIndex >= posts.length) {
                    return const SizedBox.shrink();
                  }
                  
                  final post = posts[adjustedIndex];
                  // Skip posts the user has hidden (persisted across refreshes)
                  if (_hiddenPosts.contains(post.id)) {
                    return const SizedBox.shrink();
                  }
                  if (post.isEvent || post.category.toLowerCase() == 'events') {
                    return EventPostCard(
                      post: post,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostReelsView(posts: posts, startIndex: adjustedIndex),
                        ),
                      ),
                    );
                  }
                  return NextdoorStylePostCard(
                    post: post,
                    initialIsLiked: _likedPostIds[post.id],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostReelsView(posts: posts, startIndex: adjustedIndex),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_newPostsCount > 0)
              _NewPostsBanner(
                count: _newPostsCount,
                onTap: () {
                  _scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut);
                  setState(() => _newPostsCount = 0);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildRetryFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 20, color: Color(0xFF8A8A8A)),
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
              child: const Icon(Icons.error_outline_rounded, size: 36, color: Color(0xFFE53935)),
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

// ─────────────────────────────────────────────────────────────
// Animated "New Posts" floating banner
// ─────────────────────────────────────────────────────────────
class _NewPostsBanner extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _NewPostsBanner({required this.count, required this.onTap});

  @override
  State<_NewPostsBanner> createState() => _NewPostsBannerState();
}

class _NewPostsBannerState extends State<_NewPostsBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: SlideTransition(
          position: _slideAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.count} new post${widget.count == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
