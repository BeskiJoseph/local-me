import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/backend_service.dart';
import '../services/auth_service.dart';
import '../utils/proxy_helper.dart';
import '../utils/safe_error.dart';
import '../core/utils/navigation_utils.dart';
import '../shared/widgets/user_avatar.dart';
import '../shared/widgets/heart_pop_overlay.dart';
import '../core/utils/haptic_service.dart';
import 'package:intl/intl.dart';
import '../widgets/comments_bottom_sheet.dart';
import '../shared/widgets/expandable_text.dart';

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
  
  // Initial pagination state
  final String? initialAfterId;
  final double? initialLastDistance;
  final String? initialLastPostId;
  final bool initialHasMore;

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
    this.initialAfterId,
    this.initialLastDistance,
    this.initialLastPostId,
    this.initialHasMore = true,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _horizontalController,
            onPageChanged: _onPageChanged,
            children: [
              // Nearby Feed
              ReelsVerticalFeed(
                feedType: 'local',
                initialPosts: widget.feedType == 'local' ? widget.posts : [],
                startIndex: widget.feedType == 'local' ? widget.startIndex : 0,
                postId: widget.feedType == 'local' ? widget.postId : null,
                userCity: widget.userCity,
                userCountry: widget.userCountry,
                initialAfterId: widget.feedType == 'local' ? widget.initialAfterId : null,
                initialLastDistance: widget.feedType == 'local' ? widget.initialLastDistance : null,
                initialLastPostId: widget.feedType == 'local' ? widget.initialLastPostId : null,
                initialHasMore: widget.feedType == 'local' ? widget.initialHasMore : true,
                isActiveTab: _activeTabIndex == 0,
              ),
              // Global Feed
              ReelsVerticalFeed(
                feedType: 'global',
                initialPosts: widget.feedType == 'global' ? widget.posts : [],
                startIndex: widget.feedType == 'global' ? widget.startIndex : 0,
                postId: widget.feedType == 'global' ? widget.postId : null,
                userCity: widget.userCity,
                userCountry: widget.userCountry,
                initialAfterId: widget.feedType == 'global' ? widget.initialAfterId : null,
                initialHasMore: widget.feedType == 'global' ? widget.initialHasMore : true,
                isActiveTab: _activeTabIndex == 1,
              ),
            ],
          ),

          // Top Header (Nearby | Global)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
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
class ReelsVerticalFeed extends StatefulWidget {
  final String feedType;
  final List<Post> initialPosts;
  final int startIndex;
  final String? postId;
  final String? userCity;
  final String? userCountry;
  final String? initialAfterId;
  final double? initialLastDistance;
  final String? initialLastPostId;
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
    this.initialAfterId,
    this.initialLastDistance,
    this.initialLastPostId,
    this.initialHasMore = true,
    required this.isActiveTab,
  });

  @override
  State<ReelsVerticalFeed> createState() => _ReelsVerticalFeedState();
}

class _ReelsVerticalFeedState extends State<ReelsVerticalFeed> with AutomaticKeepAliveClientMixin {
  late PageController _pageController;
  late int _currentIndex;
  List<Post> _currentPosts = [];
  bool _isLoading = false;
  String? _error;

  bool _hasMore = true;
  String? _afterId;
  double? _lastDistance;
  String? _lastPostId;
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    _currentPosts = List.from(widget.initialPosts);
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
    
    _afterId = widget.initialAfterId;
    _lastDistance = widget.initialLastDistance;
    _lastPostId = widget.initialLastPostId;
    _hasMore = widget.initialHasMore;

    _pageController.addListener(_onPageScroll);

    if (_currentPosts.isEmpty) {
      if (widget.postId != null) {
        _fetchSinglePost();
      } else {
        _loadInitialPosts();
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    if (_pageController.page! >= _currentPosts.length - 2 && 
        _hasMore && 
        !_isFetchingMore && 
        !_isLoading) {
      _loadMorePosts();
    }
  }

  Future<void> _loadInitialPosts() async {
    setState(() => _isLoading = true);
    try {
      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        mediaType: 'video',
        limit: 10,
      );
      if (mounted) {
        setState(() {
          _currentPosts = response.data;
          _afterId = response.nextCursor;
          _lastDistance = response.lastDistance;
          _lastPostId = response.lastPostId;
          _hasMore = response.hasMore;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isFetchingMore) return;
    setState(() => _isFetchingMore = true);
    try {
      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        afterId: widget.feedType == 'local' ? null : _afterId,
        lastDistance: widget.feedType == 'local' ? _lastDistance : null,
        lastPostId: widget.feedType == 'local' ? _lastPostId : null,
        mediaType: 'video',
        limit: 10,
      );
      if (mounted) {
        setState(() {
          _currentPosts.addAll(response.data);
          _afterId = response.nextCursor;
          _lastDistance = response.lastDistance;
          _lastPostId = response.lastPostId;
          _hasMore = response.hasMore;
        });
      }
    } catch (e) {
      debugPrint('Error loading more reels: $e');
    } finally {
      if (mounted) setState(() => _isFetchingMore = false);
    }
  }

  Future<void> _fetchSinglePost() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final post = await PostService.getPost(widget.postId!);
      if (post != null) {
        if (mounted) {
          setState(() {
            _currentPosts = [post];
            _currentIndex = 0;
            _isLoading = false;
          });
          // Also load more context
          _loadMorePosts();
        }
      } else {
        if (mounted) setState(() { _error = "Failed to load post"; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: widget.postId != null ? _fetchSinglePost : _loadInitialPosts, child: const Text('Retry')),
          ],
        ),
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _currentPosts.length,
      onPageChanged: (index) => setState(() => _currentIndex = index),
      itemBuilder: (context, index) {
        return ReelPostItem(
          key: ValueKey(_currentPosts[index].id),
          post: _currentPosts[index],
          isCurrentPage: index == _currentIndex && widget.isActiveTab,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual Reel Item (Unchanged but ensuring consistency)
// ─────────────────────────────────────────────────────────────
class ReelPostItem extends StatefulWidget {
  final Post post;
  final bool isCurrentPage;

  const ReelPostItem({
    super.key,
    required this.post,
    required this.isCurrentPage,
  });

  @override
  State<ReelPostItem> createState() => _ReelPostItemState();
}

class _ReelPostItemState extends State<ReelPostItem> with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _isLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _isLikeBusy = false;
  bool _isFollowed = false;
  bool _isFollowBusy = false;
  final List<Key> _activeHearts = [];
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
    _isFollowed = widget.post.isFollowing;
    if (widget.isCurrentPage) _initializeMedia();

    // Sync with global events (likes/comments from Feed or other Reels)
    _eventSub = PostService.events.listen((event) {
      if (!mounted) return;
      if (event.type == FeedEventType.postLiked) {
        final data = event.data as Map<String, dynamic>;
        if (data['postId'] == widget.post.id) {
          setState(() {
            _isLiked = data['isLiked'];
            _likeCount = data['likeCount'];
          });
        }
      } else if (event.type == FeedEventType.commentAdded) {
        final data = event.data as Map<String, dynamic>;
        if (data['postId'] == widget.post.id) {
          setState(() => _commentCount = data['commentCount']);
        }
      }
    });
  }

  @override
  void didUpdateWidget(ReelPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(ProxyHelper.getUrl(widget.post.mediaUrl!)),
      )..initialize().then((_) {
          if (!mounted) return;
          setState(() { _isInitialized = true; });
          if (widget.isCurrentPage) _videoController?.play();
          _videoController?.setLooping(true);
        });
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    if (!_isLiked) _toggleLike();
    final heartKey = UniqueKey();
    setState(() => _activeHearts.add(heartKey));
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _activeHearts.remove(heartKey));
    });
  }

  Future<void> _toggleLike() async {
    if (_isLikeBusy) return;
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() { _isLikeBusy = true; _isLiked = !_isLiked; _likeCount += _isLiked ? 1 : -1; });
    if (_isLiked) HapticService.medium();
    try {
      final response = await BackendService.toggleLike(widget.post.id);
      if (!response.success) throw response.error ?? "Failed";
      // Emit global event so Feed and other screens stay in sync
      if (mounted) {
        PostService.emit(FeedEvent(
          FeedEventType.postLiked,
          {'postId': widget.post.id, 'isLiked': _isLiked, 'likeCount': _likeCount},
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _isLiked = !_isLiked; _likeCount += _isLiked ? 1 : -1; });
    } finally {
      if (mounted) setState(() => _isLikeBusy = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowBusy) return;
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() { _isFollowBusy = true; _isFollowed = !_isFollowed; });
    try {
      final response = await BackendService.toggleFollow(widget.post.authorId);
      if (!response.success) throw response.error ?? "Failed";
    } catch (e) {
      if (mounted) setState(() => _isFollowed = !_isFollowed);
    } finally {
      if (mounted) setState(() => _isFollowBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      onTap: () {
        if (widget.post.mediaType == 'video') {
          if (_videoController?.value.isPlaying ?? false) {
            _videoController?.pause();
          } else {
            _videoController?.play();
          }
          setState(() {});
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildMedia(),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x4D000000), Colors.transparent, Color(0xCC000000)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          ..._activeHearts.map((k) => HeartPopOverlay(key: k)),
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              children: [
                _ReelActionButton(
                  icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.red : Colors.white,
                  label: '$_likeCount',
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 20),
                _ReelActionButton(
                  icon: Icons.chat_bubble_outline,
                  color: Colors.white,
                  label: '$_commentCount',
                  onTap: () => CommentsBottomSheet.show(context, widget.post),
                ),
                const SizedBox(height: 20),
                _ReelActionButton(
                  icon: Icons.send_outlined,
                  color: Colors.white,
                  label: '',
                  onTap: () {},
                ),
              ],
            ),
          ),
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
                      onTap: () => NavigationUtils.navigateToProfile(context, widget.post.authorId),
                      child: UserAvatar(
                        imageUrl: widget.post.authorProfileImage,
                        name: widget.post.authorName,
                        radius: 18,
                        initialsColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.post.authorName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (AuthService.currentUser?.uid != widget.post.authorId)
                      GestureDetector(
                        onTap: _toggleFollow,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white54, width: 1),
                            borderRadius: BorderRadius.circular(6),
                            color: _isFollowed ? Colors.white24 : Colors.transparent,
                          ),
                          child: Text(
                            _isFollowed ? 'Following' : 'Follow',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ExpandableText(
                  text: widget.post.title,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  linkStyle: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (widget.post.body.isNotEmpty && widget.post.body != widget.post.title) ...[
                  const SizedBox(height: 4),
                  ExpandableText(
                    text: widget.post.body,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                    linkStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 8),
                if (widget.post.isEvent && widget.post.eventStartDate != null)
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d, h:mm a').format(widget.post.eventStartDate!),
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (widget.post.mediaType == 'video' && _videoController != null && !_videoController!.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow, size: 80, color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.post.mediaType == 'video' && _videoController != null) {
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
    } else if (widget.post.mediaUrl != null) {
      return CachedNetworkImage(
        imageUrl: ProxyHelper.getUrl(widget.post.mediaUrl!),
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else {
      return Container(color: Colors.grey[900]);
    }
  }
}

class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ReelActionButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ],
      ),
    );
  }
}
