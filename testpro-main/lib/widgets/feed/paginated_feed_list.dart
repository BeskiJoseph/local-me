import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../services/backend_service.dart';
import '../../core/state/feed_controller.dart';
import '../../core/state/feed_session.dart';
import '../../models/post.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';

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
  final Map<String, bool> _likedPostIds = {};
  
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
          return const Center(child: CircularProgressIndicator());
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
                      color: Colors.blue.withOpacity(0.05),
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
                  if (post.isEvent || post.category.toLowerCase() == 'events') {
                    return EventPostCard(post: post);
                  }
                  return NextdoorStylePostCard(
                    post: post,
                    initialIsLiked: _likedPostIds[post.id],
                  );
                },
              ),
            ),
            if (_newPostsCount > 0)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _scrollController.animateTo(0,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOut);
                      setState(() => _newPostsCount = 0);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '↑ $_newPostsCount new posts nearby',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
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
          const Text('Failed to load more posts'),
          TextButton(
            onPressed: () => _loadMorePosts(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $error'),
          ElevatedButton(
            onPressed: () => _loadMorePosts(refresh: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String feedType) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.post_add, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No $feedType posts available',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
