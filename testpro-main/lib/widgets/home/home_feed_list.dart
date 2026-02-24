import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../services/auth_service.dart';
import '../../models/post.dart';
import '../../models/paginated_response.dart';
import '../../config/app_theme.dart';
import '../../shared/widgets/user_avatar.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/post_type_selector_sheet.dart';
import '../../core/session/user_session.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
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
        if (snapshot.connectionState == ConnectionState.waiting && _feedFuture != null) {
          return const Center(
              child: CircularProgressIndicator(color: AppTheme.primary));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }

        final response = snapshot.data;
        final posts = response?.data ?? [];

        final filteredPosts = widget.searchQuery.isEmpty
            ? posts
            : posts.where((post) {
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
            // top = 0 so "Create Post" bar sits flush under the toggle
            padding: const EdgeInsets.only(top: 0, bottom: 100),
            itemCount: filteredPosts.length + 1, // +1 for Create Post bar
            separatorBuilder: (context, index) => Container(
              height: 10,
              color: const Color(0xFFF2F2F2), // slightly lighter thick gray
            ),
            itemBuilder: (context, index) {
              // First item = "Create Post..." bar
              if (index == 0) {
                return const _CreatePostBar();
              }
              final post = filteredPosts[index - 1];
              if (post.isEvent) {
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
// "Create Post..." bar — matches screenshot exactly
// White card, user avatar, placeholder text
// ─────────────────────────────────────────────────────────────
class _CreatePostBar extends StatelessWidget {
  const _CreatePostBar();

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => const PostTypeSelectorSheet(),
        );
      },
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA), // subtle light gray background for the inner pill
            borderRadius: BorderRadius.circular(30), // fully rounded pill
          ),
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: UserSession.current,
                builder: (context, sessionData, _) {
                  final displayAvatar = sessionData?.avatarUrl ?? user?.photoURL;
                  final displayName = sessionData?.displayName ?? user?.displayName ?? user?.email?.split('@')[0] ?? 'You';
                  return UserAvatar(
                    imageUrl: displayAvatar,
                    name: displayName,
                    radius: 18,
                    backgroundColor: AppTheme.primaryLight,
                    initialsColor: AppTheme.primary,
                  );
                }
              ),
              const SizedBox(width: 12),
              const Text(
                'Create Post...',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 15,
                  color: Color(0xFF8A8A8A),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
