import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../models/post.dart';
import '../../models/paginated_response.dart';
import '../../config/app_theme.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';

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

  Future<PaginatedResponse<Post>>? _feedFuture;
  String? _futureFeedType;
  String? _futureCity;
  String? _futureCountry;
  
  // Static cache to persist posts across navigation
  static final Map<String, PaginatedResponse<Post>> _postsCache = {};

  @override
  bool get wantKeepAlive => true;
  
  String get _cacheKey => '${widget.feedType}_${widget.userCity}_${widget.userCountry}';

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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<PaginatedResponse<Post>> _getFuture() {
    final paramsChanged = _futureFeedType != widget.feedType ||
        _futureCity != widget.userCity ||
        _futureCountry != widget.userCountry;

    if (_feedFuture == null || paramsChanged) {
      _futureFeedType = widget.feedType;
      _futureCity = widget.userCity;
      _futureCountry = widget.userCountry;
      _feedFuture = PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        limit: 20, // Initial load limit
      );
    }
    return _feedFuture!;
  }

  /// Public method to force feed refresh (called after post creation)
  void refreshFeed() {
    _postsCache.remove(_cacheKey); // Clear cache
    setState(() {
      _feedFuture = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoadingLocation) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
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
              Text(widget.locationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onRetryLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Location'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.feedType == 'local' && widget.userCity == null) {
      return const Center(child: Text('Waiting for location...'));
    }
    if (widget.feedType == 'global' && widget.userCountry == null) {
      return const Center(child: Text('Waiting for location...'));
    }

    return FutureBuilder<PaginatedResponse<Post>>(
      future: _getFuture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _feedFuture != null && !_postsCache.containsKey(_cacheKey)) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }

        if (snapshot.hasError && !_postsCache.containsKey(_cacheKey)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }

        // Cache successful response
        if (snapshot.hasData && snapshot.data != null) {
          _postsCache[_cacheKey] = snapshot.data!;
        }

        final response = snapshot.data ?? _postsCache[_cacheKey];
        final posts = response?.data ?? [];
        
        final filteredPosts = widget.searchQuery.isEmpty
            ? posts.where((post) {
                // Hide archived events from the feed entirely
                if (post.isEvent && post.computedStatus == 'archived') return false;
                return true;
              }).toList()
            : posts.where((post) {
                // Hide archived events from the feed entirely
                if (post.isEvent && post.computedStatus == 'archived') return false;
                final q = widget.searchQuery.toLowerCase();
                return post.title.toLowerCase().contains(q) ||
                    post.body.toLowerCase().contains(q) ||
                    post.authorName.toLowerCase().contains(q) ||
                    post.category.toLowerCase().contains(q);
              }).toList();

        if (filteredPosts.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async { refreshFeed(); },
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
                        Icon(Icons.forum_outlined,
                            size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          widget.searchQuery.isEmpty
                              ? 'No posts yet in this area'
                              : 'No posts found',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                        if (widget.searchQuery.isEmpty &&
                            widget.userCity != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${widget.userCity}, ${widget.userCountry}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
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
          onRefresh: () async { refreshFeed(); },
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
