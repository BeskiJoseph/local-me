import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/interest_picker_screen.dart';
import '../../screens/post_reels_view.dart';
import '../../utils/debounce.dart';
import '../../utils/safe_error.dart';
import '../../mixins/post_loader_mixin.dart';

/// A specialized widget to handle the personalized recommendation feed
class RecommendedFeedList extends ConsumerStatefulWidget {
  const RecommendedFeedList({super.key});

  @override
  ConsumerState<RecommendedFeedList> createState() =>
      _RecommendedFeedListState();
}

class _RecommendedFeedListState extends ConsumerState<RecommendedFeedList>
    with AutomaticKeepAliveClientMixin, PostLoaderMixin {
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool?> _likedPostIds = {};
  
  // PostLoaderMixin implementation
  List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  
  @override
  List<Post> get posts => _posts;
  
  @override
  set posts(List<Post> value) {
    if (mounted) setState(() => _posts = value);
  }
  
  @override
  bool get isLoading => _isLoading;
  
  @override
  set isLoading(bool value) {
    if (mounted) setState(() => _isLoading = value);
  }
  
  @override
  bool get hasMore => _hasMore;
  
  @override
  set hasMore(bool value) => _hasMore = value;
  
  @override
  Map<String, bool> get likedPostIds => _likedPostIds.cast<String, bool>();
  
  @override
  String? get feedType => 'hybrid';
  
  @override
  String? get userCity => null;
  
  @override
  String? get userCountry => null;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    loadPosts();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    Debounce.run('scroll_feed', () {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoading &&
          _hasMore) {
        loadPosts();
      }
    });
  }

  @override
  void dispose() {
    Debounce.cancel('scroll_feed');
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin

    return RefreshIndicator(
      onRefresh: () => loadPosts(refresh: true),
      color: const Color(0xFF6C5CE7),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            if (_isLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return _buildRetryFooter();
          }
          final post = _posts[index];
          // Hide archived/expired events
          if ((post.isEvent || post.category.toLowerCase() == 'events') &&
              post.computedStatus == 'archived') {
            return const SizedBox.shrink();
          }
              // Route events to EventPostCard
              if (post.isEvent || post.category.toLowerCase() == 'events') {
                return EventPostCard(post: post);
              }
              return NextdoorStylePostCard(
                post: post,
                initialIsLiked: _likedPostIds[post.id],
                onTap: () {
                  if (!mounted) return;
                  // 🔥 Register before navigating (not a new post - use prepend: false)
                  ref.read(postStoreProvider.notifier).registerPosts([
                    post,
                  ], forFeedType: 'global', prepend: false);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostReelsView(
                        posts: _posts,
                        startIndex: index,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildRetryFooter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text('Failed to load more posts'),
          TextButton(
            onPressed: () => loadPosts(),
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
          Text(
            safeErrorMessage(
              error,
              fallback: 'Failed to load recommendations.',
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => loadPosts(refresh: true),
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
                MaterialPageRoute(
                  builder: (context) => const InterestPickerScreen(),
                ),
              );
            },
            child: const Text('Pick Interests'),
          ),
        ],
      ),
    );
  }
}
