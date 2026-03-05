import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/social_service.dart';
import '../services/comment_service.dart';
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

class PostReelsView extends StatefulWidget {
  final List<Post> posts;
  final int startIndex;
  final String? postId;

  const PostReelsView({
    super.key,
    this.posts = const [],
    this.startIndex = 0,
    this.postId,
    // Context for pagination
    this.feedType,
    this.authorId,
    this.category,
    this.userCity,
    this.userCountry,
    // Initial pagination state
    this.initialAfterId,
    this.initialLastDistance,
    this.initialLastPostId,
    this.initialHasMore = true,
  });

  final String? feedType;
  final String? authorId;
  final String? category;
  final String? userCity;
  final String? userCountry;
  final String? initialAfterId;
  final double? initialLastDistance;
  final String? initialLastPostId;
  final bool initialHasMore;

  @override
  State<PostReelsView> createState() => _PostReelsViewState();
}

class _PostReelsViewState extends State<PostReelsView> {
  late PageController _pageController;
  late int _currentIndex;
  List<Post> _currentPosts = [];
  bool _isLoading = false;
  String? _error;

  // Pagination state
  bool _hasMore = true;
  String? _afterId;
  double? _lastDistance;
  String? _lastPostId;
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    _currentPosts = List.from(widget.posts);
    _currentIndex = widget.startIndex;
    _pageController = PageController(initialPage: widget.startIndex);
    
    // Initialize pagination state
    _afterId = widget.initialAfterId;
    _lastDistance = widget.initialLastDistance;
    _lastPostId = widget.initialLastPostId;
    _hasMore = widget.initialHasMore;

    _pageController.addListener(_onPageScroll);

    if (_currentPosts.isEmpty && widget.postId != null) {
      _fetchSinglePost();
    }
    
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    
    // Pre-fetch when we're 2 pages from the end
    if (_pageController.page! >= _currentPosts.length - 2 && 
        _hasMore && 
        !_isFetchingMore && 
        !_isLoading) {
      _loadMorePosts();
    }
  }

  Future<void> _loadMorePosts() async {
    if (!_hasMore || _isFetchingMore || widget.feedType == null) return;

    setState(() => _isFetchingMore = true);

    try {
      final response = await PostService.getPostsPaginated(
        feedType: widget.feedType!,
        authorId: widget.authorId,
        category: widget.category,
        userCity: widget.userCity,
        userCountry: widget.userCountry,
        afterId: widget.feedType == 'local' ? null : _afterId,
        lastDistance: widget.feedType == 'local' ? _lastDistance : null,
        lastPostId: widget.feedType == 'local' ? _lastPostId : null,
        limit: 10,
      );

      final nextPosts = response.data;
      
      if (mounted) {
        setState(() {
          _currentPosts.addAll(nextPosts);
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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await BackendService.getPost(widget.postId!);
      if (response.success && response.data != null) {
        if (mounted) {
          setState(() {
            _currentPosts = [Post.fromJson(response.data!)];
            _currentIndex = 0;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = response.error ?? "Failed to load post";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchSinglePost,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _currentPosts.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return ReelPostItem(
                key: ValueKey(_currentPosts[index].id),
                post: _currentPosts[index],
                isCurrentPage: index == _currentIndex,
              );
            },
          ),
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reels',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
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
  bool _showComments = false;
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLikeBusy = false;
  bool _isFollowed = false;
  bool _isFollowBusy = false;
  final List<Key> _activeHearts = [];

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
    _isFollowed = widget.post.isFollowing;
    if (widget.isCurrentPage) {
      _initializeMedia();
    }
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
          setState(() {
            _isInitialized = true;
          });
          if (widget.isCurrentPage) {
            _videoController?.play();
          }
          _videoController?.setLooping(true);
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _handleDoubleTap() async {
    if (!_isLiked) {
      _toggleLike();
    }
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

    setState(() {
      _isLikeBusy = true;
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });

    if (_isLiked) HapticService.medium();

    try {
      final response = await BackendService.toggleLike(widget.post.id);
      if (!response.success) throw response.error ?? "Failed";
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount += _isLiked ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLikeBusy = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowBusy) return;
    final user = AuthService.currentUser;
    if (user == null) return;

    setState(() {
      _isFollowBusy = true;
      _isFollowed = !_isFollowed;
    });

    try {
      final response = await BackendService.toggleFollow(widget.post.authorId);
      if (!response.success) throw response.error ?? "Failed";
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowed = !_isFollowed;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFollowBusy = false;
        });
      }
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
          // Background media
          _buildMedia(),

          // Gradient overlay
          Container(
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

          // Double-tap heart animation
          ..._activeHearts.map((k) => HeartPopOverlay(key: k)),

          // Right action buttons
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
                  label: '${widget.post.commentCount}',
                  onTap: () => CommentsBottomSheet.show(context, widget.post),
                ),
                const SizedBox(height: 20),
                _ReelActionButton(
                  icon: Icons.send_outlined,
                  color: Colors.white,
                  label: '',
                  onTap: () {
                    // TODO: Share
                  },
                ),
              ],
            ),
          ),

          // Bottom info
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
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
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  widget.post.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (widget.post.body.isNotEmpty && widget.post.body != widget.post.title) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.post.body,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
          
          // Video Play/Pause Indicator
          if (widget.post.mediaType == 'video' && _videoController != null && !_videoController!.value.isPlaying)
            const Center(
              child: Icon(Icons.play_arrow, size: 80, color: Colors.white54),
            ),
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

  const _ReelActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
