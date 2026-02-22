import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../models/post.dart';
import '../../models/paginated_response.dart';
import '../../services/backend_service.dart';
import '../../services/location_service.dart';
import '../post_card.dart';
import '../nextdoor_post_card.dart';

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
  final List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _cursor;
  String? _error;
  final Map<String, bool> _likedPostIds = {};
  
  // Debounce scroll triggers to prevent rapid-fire requests
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
      case FeedEventType.postCreated:
        // For a true production app, we'd check if the new post matches 
        // this feed's criteria (city, category, etc.)
        // For now, we refresh to ensure correct sorting and data integrity
        _loadMorePosts(refresh: true);
        break;
      case FeedEventType.postDeleted:
        setState(() {
          _posts.removeWhere((p) => p.id == event.data);
        });
        break;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _eventSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _loadMorePosts({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;

    debugPrint('🚀 FEED API CALLED: ${widget.feedType}');

    if (refresh) {
      if (mounted) {
        setState(() {
          _posts.clear();
          _cursor = null;
          _hasMore = true;
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
      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        afterId: _cursor,
        limit: 10,
      );

      final data = response.data;
      final nextCursor = response.nextCursor;

      if (mounted) {
        setState(() {
          if (refresh) {
            _posts.clear();
            _likedPostIds.clear();
          }
          
          final existingIds = _posts.map((p) => p.id).toSet();
          final uniqueNew = data.where((p) => !existingIds.contains(p.id)).toList();
          
          _posts.addAll(uniqueNew);
          
          _cursor = nextCursor;
          _hasMore = response.hasMore;
          
          if (_posts.isEmpty && !refresh) {
            _hasMore = false;
          }
          
          for (var p in data) {
            _likedPostIds[p.id] = p.isLiked;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading posts: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    await _loadMorePosts(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    if (_posts.isEmpty && _isLoading) {
      return _buildLoadingState();
    }
    
    if (_error != null && _posts.isEmpty) {
      return _buildErrorState(_error!);
    }

    if (_posts.isEmpty && !_isLoading) {
      return _buildEmptyState(widget.feedType);
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
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
          return NextdoorStylePostCard(
            post: post,
            initialIsLiked: _likedPostIds[post.id],
          );
        },
      ),
    );
  }

  void _loadMorePostsManual({bool refresh = false}) {
    _loadMorePosts(refresh: refresh);
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

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildShimmer(40, 40, isCircle: true),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShimmer(100, 12),
                      const SizedBox(height: 4),
                      _buildShimmer(60, 10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildShimmer(double.infinity, 12),
              const SizedBox(height: 4),
              _buildShimmer(double.infinity, 12),
              const SizedBox(height: 4),
              _buildShimmer(200, 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmer(double width, double height, {bool isCircle = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: isCircle ? null : BorderRadius.circular(8),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFFF7675)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B9D).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.error_outline, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Text(
            'Oops! Something went wrong',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Please try again',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF0984E3)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _loadMorePostsManual(refresh: true),
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String feedType) {
    String title;
    String subtitle;
    IconData icon;

    switch (feedType) {
      case 'local':
        title = 'No local posts yet';
        subtitle = 'Be the first to share in your area!';
        icon = Icons.location_on;
        break;
      case 'global':
        title = 'No global posts yet';
        subtitle = 'Share your voice with the world!';
        icon = Icons.public;
        break;
      default:
        title = 'No posts yet';
        subtitle = 'Be the first to post!';
        icon = Icons.post_add;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C5CE7), Color(0xFF0984E3)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withOpacity(0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00D2A0), Color(0xFF00CEC9)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D2A0).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // Navigate to create post
                },
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Create Post',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
