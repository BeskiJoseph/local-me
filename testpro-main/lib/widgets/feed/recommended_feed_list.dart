import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/feed_service.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../post_card.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
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
  final List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _afterId;
  String? _error;
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  final Map<String, bool> _likedPostIds = {};
  
  Timer? _debounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMorePosts();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_debounce?.isActive ?? false) return;

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore &&
          _error == null) {
        _loadMorePosts();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMorePosts({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;

    debugPrint('🚀 RECOMMENDED FEED API CALLED');

    if (refresh) {
      if (mounted) {
        setState(() {
          _posts.clear();
          _hasMore = true;
          _afterId = null;
          _error = null;
          _isLoading = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }
    }

    try {
      final user = AuthService.currentUser;
      if (user == null) {
        if (mounted) setState(() => _error = 'User not authenticated');
        return;
      }

      final lastId = _posts.isNotEmpty ? _posts.last.id : null;
      final newPosts = await FeedService.getRecommendedFeed(
        userId: user.uid,
        sessionId: _sessionId,
        afterId: lastId,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _posts.clear();
            _likedPostIds.clear();
          }
          
          final existingIds = _posts.map((p) => p.id).toSet();
          final uniqueNew = newPosts.where((p) => !existingIds.contains(p.id));
          _posts.addAll(uniqueNew);

          for (var p in newPosts) {
            _likedPostIds[p.id] = p.isLiked;
          }

          if (newPosts.length < 10) _hasMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading recommended posts: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _posts.isEmpty) {
      return _buildErrorState(_error!);
    }

    if (_posts.isEmpty && !_isLoading) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadMorePosts(refresh: true),
      color: const Color(0xFF6C5CE7),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _posts.length + (_hasMore || _error != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            if (_error != null) {
              return _buildRetryFooter();
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final post = _posts[index];
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
