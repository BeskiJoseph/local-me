import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/feed_service.dart';
import '../../services/post_service.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../core/state/feed_controller.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../utils/safe_error.dart';
import '../../services/backend_service.dart';
import '../../screens/interest_picker_screen.dart';

/// A specialized widget to handle the personalized recommendation feed
class RecommendedFeedList extends StatefulWidget {
  const RecommendedFeedList({super.key});

  @override
  State<RecommendedFeedList> createState() => _RecommendedFeedListState();
}

class _RecommendedFeedListState extends State<RecommendedFeedList> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final FeedController _feedController = FeedController();
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Map<String, bool?> _likedPostIds = {};
  
  Timer? _debounce;
  StreamSubscription? _eventSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMorePosts();
    _scrollController.addListener(_onScroll);
    _eventSubscription = PostService.events.listen(_handleFeedEvent);
  }

  void _handleFeedEvent(FeedEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case FeedEventType.postDeleted:
        _feedController.deletePost(event.data);
        break;
      case FeedEventType.postLiked:
        final data = event.data as Map<String, dynamic>;
        setState(() {
          _likedPostIds[data['postId']] = data['isLiked'];
        });
        _feedController.updatePostLike(data['postId'], data['isLiked'], data['likeCount']);
        break;
      default:
        break;
    }
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

  @override
  void dispose() {
    _debounce?.cancel();
    _eventSubscription?.cancel();
    _scrollController.dispose();
    _feedController.dispose();
    super.dispose();
  }

  Future<void> _loadMorePosts({bool refresh = false}) async {
    if (_feedController.isLoading) return;
    if (!refresh && !_feedController.hasMore) return;

    debugPrint('🚀 RECOMMENDED FEED API CALLED');

    if (refresh) {
      _feedController.clear(notify: false);
      _likedPostIds.clear();
      _feedController.setLoading(true);
    } else {
      _feedController.setLoading(true);
      _feedController.setError(null);
    }

    try {
      final user = AuthService.currentUser;
      if (user == null) {
        if (mounted) _feedController.setError('User not authenticated');
        return;
      }

      final lastId = _feedController.cursor;
      final newPosts = await FeedService.getRecommendedFeed(
        userId: user.uid,
        sessionId: _sessionId,
        afterId: lastId,
        limit: 10,
      );

      if (mounted) {
        for (var p in newPosts) {
          _likedPostIds[p.id] = p.isLiked;
        }
        _feedController.appendPosts(
          newPosts, 
          refresh: refresh, 
          nextCursor: newPosts.length == 10 ? newPosts.last.id : null
        );
      }
    } catch (e) {
      debugPrint('Error loading recommended posts: $e');
      if (mounted) _feedController.setError(e.toString());
    } finally {
      if (mounted) _feedController.setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    
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
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: () => _loadMorePosts(refresh: true),
          color: const Color(0xFF6C5CE7),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            itemCount: posts.length + (hasMore || error != null ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == posts.length) {
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
              final post = posts[index];
              // Hide archived/expired events
              if ((post.isEvent || post.category.toLowerCase() == 'events') 
                  && post.computedStatus == 'archived') {
                return const SizedBox.shrink();
              }
              // Route events to EventPostCard
              if (post.isEvent || post.category.toLowerCase() == 'events') {
                return EventPostCard(post: post);
              }
              return NextdoorStylePostCard(
                post: post,
                initialIsLiked: _likedPostIds[post.id],
              );
            },
          ),
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
          Text(safeErrorMessage(error, fallback: 'Failed to load recommendations.')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadMorePosts(refresh: true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No recommendations yet. Interact more!'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const InterestPickerScreen()),
              );
            },
            child: const Text('Pick Interests'),
          ),
        ],
      ),
    );
  }
}
