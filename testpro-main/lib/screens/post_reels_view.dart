import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:testpro/config/app_theme.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/services/auth_service.dart';
import 'package:testpro/core/utils/haptic_service.dart';
import 'package:testpro/core/utils/navigation_utils.dart';
import 'package:testpro/utils/proxy_helper.dart';
import 'package:testpro/utils/debounce.dart';
import 'package:testpro/services/interaction_service.dart';
import 'package:testpro/widgets/feed/paginated_feed_list.dart';
import 'package:testpro/widgets/comments_bottom_sheet.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/shared/widgets/user_avatar.dart';
import 'package:testpro/shared/widgets/heart_pop_overlay.dart';
import 'package:intl/intl.dart';
import 'package:testpro/shared/widgets/expandable_text.dart';
import 'package:testpro/widgets/event_card/event_details_section.dart';
import 'package:testpro/widgets/event_card/event_attendance_section.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'artizone_page.dart';

class PostReelsView extends StatefulWidget {
  final List<Post> posts;
  final int startIndex;
  final String? postId;
  final String? feedType; // 'local' or 'global'

  // Context for pagination
  final String? authorId;
  final String? category;
  final String? userCity;
  final String? userCountry;
  final bool initialHasMore;
  final bool isActiveTab;

  const PostReelsView({
    super.key,
    this.posts = const [],
    this.startIndex = 0,
    this.postId,
    this.feedType = 'local',
    this.authorId,
    this.category,
    this.userCity,
    this.userCountry,
    this.initialHasMore = true,
    this.isActiveTab = true,
  });

  @override
  State<PostReelsView> createState() => _PostReelsViewState();
}

class _PostReelsViewState extends State<PostReelsView> {
  late PageController _horizontalController;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('📽️ REELS OPENED: hasMore=${widget.initialHasMore}');
    _activeTabIndex = widget.feedType == 'global' ? 1 : 0;
    _horizontalController = PageController(initialPage: _activeTabIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _activeTabIndex = index;
    });
    HapticService.light();
  }

  @override
  Widget build(BuildContext context) {
    final isProfileMode = widget.authorId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isProfileMode)
            ReelsVerticalFeed(
              feedType: 'profile', // Unique feed type for profiles
              initialPosts: widget.posts,
              startIndex: widget.startIndex,
              postId: widget.postId,
              authorId: widget.authorId,
              initialHasMore: widget.initialHasMore,
              isActiveTab: true,
            )
          else
            PageView(
              controller: _horizontalController,
              onPageChanged: _onPageChanged,
              children: [
                // LOCAL TAB (handles both 'local' and 'hybrid' feed types)
                ReelsVerticalFeed(
                  feedType: 'hybrid',
                  initialPosts: (widget.feedType == 'local' || widget.feedType == 'hybrid') ? widget.posts : [],
                  startIndex: (widget.feedType == 'local' || widget.feedType == 'hybrid') ? widget.startIndex : 0,
                  postId: (widget.feedType == 'local' || widget.feedType == 'hybrid') ? widget.postId : null,
                  userCity: widget.userCity,
                  userCountry: widget.userCountry,
                  initialHasMore: widget.initialHasMore,
                  isActiveTab: _activeTabIndex == 0,
                  authorId: widget.authorId,
                ),
                // GLOBAL TAB
                ReelsVerticalFeed(
                  feedType: 'global',
                  initialPosts: widget.feedType == 'global' ? widget.posts : [],
                  startIndex: widget.feedType == 'global' ? widget.startIndex : 0,
                  postId: widget.feedType == 'global' ? widget.postId : null,
                  userCity: widget.userCity,
                  userCountry: widget.userCountry,
                  initialHasMore: widget.initialHasMore,
                  isActiveTab: _activeTabIndex == 1,
                  authorId: widget.authorId,
                ),
              ],
            ),

          // Top Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (!isProfileMode) ...[
                    const SizedBox(width: 8),
                    _TabButton(
                      label: 'Nearby',
                      isActive: _activeTabIndex == 0,
                      onTap: () => _horizontalController.animateToPage(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      ),
                    ),
                    const SizedBox(width: 24),
                    _TabButton(
                      label: 'Global',
                      isActive: _activeTabIndex == 1,
                      onTap: () => _horizontalController.animateToPage(
                        1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
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
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? Colors.white : Colors.white60,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: isActive ? 24 : 0,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Vertical Immersive Feed (Moved from PostReelsView)
// ─────────────────────────────────────────────────────────────
class ReelsVerticalFeed extends ConsumerStatefulWidget {
  final String feedType;
  final List<Post> initialPosts;
  final int startIndex;
  final String? postId;
  final String? userCity;
  final String? userCountry;
  final String? authorId;
  final bool initialHasMore;

  final bool isActiveTab;

  const ReelsVerticalFeed({
    super.key,
    required this.feedType,
    this.initialPosts = const [],
    this.startIndex = 0,
    this.postId,
    this.userCity,
    this.userCountry,
    this.authorId,
    required this.isActiveTab,
    this.initialHasMore = true,
  });

  @override
  ConsumerState<ReelsVerticalFeed> createState() => _ReelsVerticalFeedState();
}

class _ReelsVerticalFeedState extends ConsumerState<ReelsVerticalFeed>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 🔥 PURE ARCHITECTURE: Fetch from Screen/Controller
    if (widget.initialPosts.isEmpty) {
      Future.microtask(() {
        if (!mounted) return;
        _loadFeed();
      });
    } else {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(postStoreProvider.notifier)
            .registerPosts(widget.initialPosts, forFeedType: widget.feedType, prepend: false);
      });
    }
  }

  Future<void> _loadFeed() async {
    // 🔥 Reset state before fetching to clear hasMore/error flags
    ref.read(postStoreProvider.notifier).resetFeedState(widget.feedType);
    
    try {
      final response = (widget.authorId != null)
          ? await PostService.getFilteredPostsPaginated(
              authorId: widget.authorId,
              limit: 20,
            )
          : await PostService.getPostsPaginated(
              feedType: widget.feedType,
              userCity: widget.userCity,
              userCountry: widget.userCountry,
              mediaType: 'video',
              limit: 20,
            );

      if (mounted) {
        ref
            .read(postStoreProvider.notifier)
            .registerPosts(response.data, forFeedType: widget.feedType, prepend: false);
      }
    } catch (e) {
      debugPrint('Error loading Reels: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PaginatedFeedList(
      feedType: widget.feedType,
      authorId: widget.authorId,
      userCity: widget.userCity,
      userCountry: widget.userCountry,
      layoutType: FeedLayoutType.paged,
      mediaType: 'video',
      initialPosts: widget.initialPosts,
      startIndex: widget.startIndex,
      initialHasMore: widget.initialHasMore,
      onRefresh: _loadFeed,
      itemBuilder: (context, post, index, isCurrent) {
        return ReelPostItem(
          key: ValueKey(post.id),
          post: post,
          isCurrentPage: isCurrent && widget.isActiveTab,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual Reel Item (Unchanged but ensuring consistency)
// ─────────────────────────────────────────────────────────────
class ReelPostItem extends ConsumerStatefulWidget {
  final Post post;
  final bool isCurrentPage;

  const ReelPostItem({
    super.key,
    required this.post,
    required this.isCurrentPage,
  });

  @override
  ConsumerState<ReelPostItem> createState() => _ReelPostItemState();
}

class _ReelPostItemState extends ConsumerState<ReelPostItem>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  final List<Key> _activeHearts = [];

  @override
  void initState() {
    super.initState();
    if (widget.isCurrentPage) _initializeMedia();

    // 🔥 Ensure post is initialized in global state for real-time sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(postStoreProvider.notifier).registerPosts([
          widget.post,
        ], forFeedType: 'reels', prepend: false);
      }
    });
  }

  @override
  void didUpdateWidget(ReelPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update global state if widget post changes
    if (oldWidget.post.id != widget.post.id) {
      ref.read(postStoreProvider.notifier).registerPosts([
        widget.post,
      ], forFeedType: 'reels', prepend: false);
    }

    if (widget.isCurrentPage && !oldWidget.isCurrentPage) {
      if (_videoController == null) {
        _initializeMedia();
      } else {
        _videoController?.play();
      }
    } else if (!widget.isCurrentPage && oldWidget.isCurrentPage) {
      _videoController?.pause();
    }
  }

  void _initializeMedia() {
    if (widget.post.mediaType == 'video' && widget.post.mediaUrl != null) {
      _videoController =
          VideoPlayerController.networkUrl(
              Uri.parse(ProxyHelper.getUrl(widget.post.mediaUrl!)),
            )
            ..initialize().then((_) {
              if (!mounted) return;
              setState(() {
                _isInitialized = true;
              });
              if (widget.isCurrentPage) _videoController?.play();
              _videoController?.setLooping(true);
            });
    }
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    final post = ref.read(postProvider(widget.post.id)) ?? widget.post;
    if (!post.isLiked) _toggleLike();

    final heartKey = UniqueKey();
    setState(() => _activeHearts.add(heartKey));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _activeHearts.remove(heartKey));
    });
  }

  Future<void> _toggleLike() async {
    await InteractionService.toggleLike(
      postId: widget.post.id,
      ref: ref,
    );
  }

  Future<void> _toggleFollow() async {
    await InteractionService.toggleFollow(
      targetUserId: widget.post.authorId,
      postId: widget.post.id,
      authorId: widget.post.authorId,
      ref: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    final interactionPost = ref.watch(postProvider(widget.post.id));
    final post = interactionPost ?? widget.post;

    // Sync with global state
    final currentIsLiked = post.isLiked;
    final currentLikeCount = post.likeCount;
    final currentCommentCount = post.commentCount;
    final isFollowing = post.isFollowing;

    final category = widget.post.category.toLowerCase();
    final isArticle = category == 'article' || category == 'artizone';

    return VisibilityDetector(
      key: ValueKey('reel_${widget.post.id}'),
      onVisibilityChanged: (info) {
        if (mounted) {
          // 🔥 Core Fix: Track visibility for global memory pruning
          ref
              .read(postStoreProvider.notifier)
              .setVisible(widget.post.id, info.visibleFraction > 0.1);
        }

        if (info.visibleFraction > 0.8 && widget.isCurrentPage && mounted) {
          _videoController?.play();
          // 🔥 MARK AS SEEN: Trigger Soft Seen system for Reels
          ref.read(postStoreProvider.notifier).markAsSeen(widget.post.id);
        } else if (info.visibleFraction == 0 && mounted) {
          _videoController?.pause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Media & Taps
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: _handleDoubleTap,
            onTap: () {
              if (isArticle) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Row(
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          color: Color(0xFF2E7D6A),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'ArtiZone',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    content: const Text(
                      'Explore more articles and stories from this user in ArtiZone.',
                      style: TextStyle(fontSize: 15),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ArtizonePage(userId: widget.post.authorId),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D6A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Go to ArtiZone'),
                      ),
                    ],
                  ),
                );
              } else if (widget.post.mediaType == 'video') {
                if (_videoController?.value.isPlaying ?? false) {
                  _videoController?.pause();
                } else {
                  _videoController?.play();
                }
                setState(() {});
              }
            },
            child: _buildMedia(),
          ),

          // Gradient Overlay (Ignore pointer to not block taps)
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x4D000000),
                    Colors.transparent,
                    Color(0xCC000000),
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          ..._activeHearts.map((k) => HeartPopOverlay(key: k)),
          // Interaction Buttons (Like, Comment, etc.)
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              children: [
                _ReelActionButton(
                  icon: currentIsLiked ? Icons.favorite : Icons.favorite_border,
                  color: currentIsLiked
                      ? Colors.red
                      : (isArticle ? Colors.black54 : Colors.white),
                  label: '$currentLikeCount',
                  labelColor: isArticle ? Colors.black87 : Colors.white,
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 20),
                _ReelActionButton(
                  icon: Icons.chat_bubble_outline,
                  color: isArticle ? Colors.black54 : Colors.white,
                  label: '$currentCommentCount',
                  labelColor: isArticle ? Colors.black87 : Colors.white,
                  onTap: () => CommentsBottomSheet.show(context, widget.post),
                ),
                const SizedBox(height: 20),
                _ReelActionButton(
                  icon: Icons.send_outlined,
                  color: isArticle ? Colors.black54 : Colors.white,
                  label: '',
                  labelColor: isArticle ? Colors.black87 : Colors.white,
                  onTap: () {},
                ),
              ],
            ),
          ),
          // Author Profile and Post Details
          Positioned(
            bottom: 70,
            left: 12,
            right: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => NavigationUtils.navigateToProfile(
                        context,
                        widget.post.authorId,
                      ),
                      child: UserAvatar(
                        imageUrl: widget.post.authorProfileImage ?? '',
                        name: widget.post.authorName.isNotEmpty ? widget.post.authorName : 'Unknown',
                        radius: 18,
                        initialsColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.post.authorName.isNotEmpty ? widget.post.authorName : 'Unknown',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isArticle ? Colors.black87 : Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (AuthService.currentUser?.uid != widget.post.authorId)
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isArticle
                                  ? Colors.black26
                                  : Colors.white54,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            color: isFollowing
                                ? (isArticle ? Colors.black12 : Colors.white24)
                                : Colors.transparent,
                          ),
                          child: Text(
                            isFollowing ? 'Following' : 'Follow',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isArticle ? Colors.black87 : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                if (widget.post.category.toLowerCase() == 'events' ||
                    widget.post.isEvent) ...[
                  // Just title and minimal description overlay if required. The main event details
                  // are now built in the _buildMedia space to represent a centered card.
                  if (widget.post.mediaUrl != null) ...[
                    Text(
                      widget.post.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (widget.post.body.isNotEmpty &&
                        widget.post.body != widget.post.title) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.post.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ] else ...[
                  ExpandableText(
                    text: widget.post.title,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    linkStyle: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (widget.post.body.isNotEmpty &&
                      widget.post.body != widget.post.title) ...[
                    const SizedBox(height: 8),
                    ExpandableText(
                      text: widget.post.body,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                      linkStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    final isArticle =
        widget.post.category.toLowerCase() == 'article' ||
        widget.post.category.toLowerCase() == 'artizone';
    final isEvent =
        widget.post.category.toLowerCase() == 'events' || widget.post.isEvent;

    if (isEvent && widget.post.mediaUrl == null) {
      // Show event as a centered card if it has no background media
      return Container(
        color: const Color(0xFFF0F0F0),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AbsorbPointer(
                      absorbing: true,
                      child: EventDetailsSection(post: widget.post),
                    ),
                    const Divider(color: Colors.black12),
                    EventAttendanceSection(post: widget.post),
                  ],
                ),
              ),
              const SizedBox(
                height: 200,
              ), // padding for the interactions at the bottom
            ],
          ),
        ),
      );
    } else if (isEvent && widget.post.mediaUrl != null) {
      // If event has an image/video, center that media and place a floating card over it in the center.
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
          // Ignore pointer on dim background so video/image tap works (but event card is above it)
          IgnorePointer(
            child: Container(
              color: Colors.black54, // dim background
            ),
          ),
          Container(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        AbsorbPointer(
                          absorbing: true,
                          child: EventDetailsSection(post: widget.post),
                        ),
                        const Divider(color: Colors.black12),
                        EventAttendanceSection(post: widget.post),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 200,
                  ), // padding for the interactions at the bottom
                ],
              ),
            ),
          ),
        ],
      );
    } else if (widget.post.mediaType == 'video' && _videoController != null) {
      return _isInitialized
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController!.value.size.width,
                height: _videoController!.value.size.height,
                child: VideoPlayer(_videoController!),
              ),
            )
          : const Center(child: CircularProgressIndicator(color: Colors.white));
    } else if (widget.post.mediaType == 'document') {
      return _buildDocumentReelCard(fullScreen: true);
    } else if (widget.post.mediaUrl != null) {
      return CachedNetworkImage(
        imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else if (isArticle) {
      return Container(
        color: const Color(0xFFF7F8FA),
        padding: const EdgeInsets.only(
          top: kToolbarHeight + 40,
          bottom: 40,
          left: 16,
          right: 16,
        ),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.post.mediaUrl != null) ...[
                  if (widget.post.mediaType == 'document')
                    _buildDocumentReelCard()
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 200,
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
                Text(
                  widget.post.title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    UserAvatar(
                      imageUrl: widget.post.authorProfileImage ?? '',
                      name: widget.post.authorName.isNotEmpty ? widget.post.authorName : 'Unknown',
                      radius: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.post.authorName.isNotEmpty ? widget.post.authorName : 'Unknown',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          Text(
                            DateFormat(
                              'MMM d, yyyy',
                            ).format(widget.post.createdAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  (widget.post.body.isNotEmpty
                          ? widget.post.body
                          : widget.post.title)
                      .replaceAll(RegExp(r'!\[.*?\]\(.*?\)\n?'), '')
                      .trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.8,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(color: Colors.grey[900]);
    }
  }

  Widget _buildDocumentReelCard({bool fullScreen = false}) {
    final fileName = widget.post.mediaUrl?.split('/').last ?? 'Document';
    final extension = fileName.split('.').last.toUpperCase();

    return Container(
      color: fullScreen ? const Color(0xFFF7F8FA) : Colors.transparent,
      padding: fullScreen ? const EdgeInsets.all(24) : EdgeInsets.zero,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: InkWell(
          onTap: () {
            final url = Uri.parse(ProxyHelper.getUrl(widget.post.mediaUrl!));
            launchUrl(url, mode: LaunchMode.externalApplication);
          },
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF4FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  extension == 'PDF'
                      ? Icons.picture_as_pdf_rounded
                      : Icons.description_rounded,
                  color: const Color(0xFF3182CE),
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${extension == 'PDF' ? 'PDF' : 'Word'} Document',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to open and read',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color? labelColor;

  const _ReelActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: labelColor ?? color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
