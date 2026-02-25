import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/social_service.dart';
import '../services/comment_service.dart';
import '../services/backend_service.dart';
import '../services/auth_service.dart';
import '../utils/proxy_helper.dart';
import '../core/utils/navigation_utils.dart';
import '../shared/widgets/user_avatar.dart';

class ReelsFeedScreen extends StatefulWidget {
  final String feedType; // 'local', 'global'
  final String? userCity;
  final String? userCountry;

  const ReelsFeedScreen({
    super.key,
    required this.feedType,
    this.userCity,
    this.userCountry,
  });

  @override
  State<ReelsFeedScreen> createState() => _ReelsFeedScreenState();
}

class _ReelsFeedScreenState extends State<ReelsFeedScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  List<Post> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final result = await BackendService.getPosts(
      lat: widget.feedType == 'global' ? null : null, // Reels expansion placeholder
      country: widget.userCountry,
      limit: 20,
    );
    
    if (result.success && mounted) {
      final data = result.data ?? [];
      final loadedPosts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      loadedPosts.shuffle();
      setState(() {
        _posts = loadedPosts;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${result.error}')),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.feedType.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _posts.isEmpty
              ? const Center(
                  child: Text(
                    'No posts available',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    return ReelPostItem(
                      key: ValueKey(_posts[index].id),
                      post: _posts[index],
                      isCurrentPage: index == _currentIndex,
                    );
                  },
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

class _ReelPostItemState extends State<ReelPostItem> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  bool _showComments = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLikeBusy = false;
  bool _isFollowed = false;
  bool _isFollowBusy = false;
  
  // Use Future instead of Stream for one-shot data to prevent API calls on every rebuild
  Future<bool>? _isLikedFuture;
  Future<bool>? _isFollowedFuture;
  Future<List<Comment>>? _commentsFuture;
  
  // Cache results to avoid redundant API calls
  bool? _cachedIsLiked;
  bool? _cachedIsFollowed;
  List<Comment>? _cachedComments;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
    _initializeFutures();
    if (widget.isCurrentPage) {
      _initializeMedia();
    }
  }
  
  void _initializeFutures() {
    final user = AuthService.currentUser;
    if (user != null && _cachedIsLiked == null) {
      _isLikedFuture = SocialService.isPostLiked(widget.post.id, user.uid)
        ..then((value) => _cachedIsLiked = value);
    }
    if (user != null && user.uid != widget.post.authorId && _cachedIsFollowed == null) {
      _isFollowedFuture = SocialService.isUserFollowed(user.uid, widget.post.authorId)
        ..then((value) => _cachedIsFollowed = value);
    }
    if (_cachedComments == null) {
      _commentsFuture = CommentService.getComments(widget.post.id)
        ..then((value) => _cachedComments = value);
    }
  }

  @override
  void didUpdateWidget(ReelPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      _isLiked = widget.post.isLiked;
      _likeCount = widget.post.likeCount;
      _isLikeBusy = false;
      _isFollowBusy = false;
      // Clear cache for new post
      _cachedIsLiked = null;
      _cachedIsFollowed = null;
      _cachedComments = null;
      _initializeFutures();
    }
    if (widget.isCurrentPage && !oldWidget.isCurrentPage) {
      if (_videoController == null) {
        _initializeMedia();
      } else {
        _videoController?.play();
      }
    } else if (!widget.isCurrentPage && oldWidget.isCurrentPage) {
      _videoController?.pause();
      // Optional: Dispose if far away to save even more memory
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
    _commentController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoController != null) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (widget.post.mediaType == 'video') {
          _togglePlayPause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media (Image or Video)
          _buildMedia(),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),

          // Content overlay
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                
                // Bottom content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Left side - Post info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Author info
                            GestureDetector(
                              onTap: () {
                                final currentUser = AuthService.currentUser;
                                if (currentUser != null && 
                                    widget.post.authorId != currentUser.uid) {
                                  NavigationUtils.navigateToProfile(context, widget.post.authorId);
                                }
                              },
                              child: Row(
                                children: [
                                  UserAvatar(
                                    imageUrl: widget.post.authorProfileImage,
                                    name: widget.post.authorName,
                                    radius: 20,
                                    initialsColor: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.post.authorName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (widget.post.city != null)
                                          Text(
                                            widget.post.city!,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.7),
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Title
                            Text(
                              widget.post.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            
                            // Description
                            Text(
                              widget.post.body,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            
                            // Category
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '#${widget.post.category}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Right side - Action buttons
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLikeButton(),
                          const SizedBox(height: 24),
                          _buildCommentButton(),
                          const SizedBox(height: 24),
                          _buildShareButton(),
                          const SizedBox(height: 24),
                          _buildFollowButton(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Play/Pause indicator for video
          if (widget.post.mediaType == 'video' && _videoController != null)
            Center(
              child: AnimatedOpacity(
                opacity: _videoController!.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
              ),
            ),

          // Comments bottom sheet
          if (_showComments)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showComments = false;
                  });
                },
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: GestureDetector(
                    onTap: () {}, // Prevent closing when tapping sheet
                    child: DraggableScrollableSheet(
                      initialChildSize: 0.6,
                      minChildSize: 0.3,
                      maxChildSize: 0.9,
                      builder: (context, scrollController) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Handle
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              
                              // Header
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Comments',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        setState(() {
                                          _showComments = false;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              
                              const Divider(height: 1),
                              
                              // Comments list
                              Expanded(
                                child: _buildCommentsList(scrollController),
                              ),
                              
                              // Comment input
                              _buildCommentInput(),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMedia() {
    if (widget.post.mediaType == 'video' && _videoController != null) {
      return _isInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            )
          : Container(
              color: Colors.grey[900],
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            );
    } else if (widget.post.mediaUrl != null) {
      return Image.network(
        ProxyHelper.getUrl(widget.post.mediaUrl!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[900],
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.white, size: 50),
            ),
          );
        },
      );
    } else {
      return Container(
        color: Colors.grey[900],
        child: const Center(
          child: Icon(Icons.image, color: Colors.white, size: 50),
        ),
      );
    }
  }

  Widget _buildLikeButton() {
    final user = AuthService.currentUser;
    if (user == null) {
      return _actionButton(
        Icons.favorite_border,
        '0',
        () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please login to like posts')),
          );
        },
      );
    }

    return FutureBuilder<bool>(
      future: _isLikedFuture,
      builder: (context, snapshot) {
        if (!_isLikeBusy && snapshot.hasData && _cachedIsLiked == null) {
          _cachedIsLiked = snapshot.data;
          _isLiked = snapshot.data ?? _isLiked;
        }
        // Use cached value if available
        final isLiked = _cachedIsLiked ?? _isLiked;
        return _actionButton(
          isLiked ? Icons.favorite : Icons.favorite_border,
          _likeCount.toString(),
          () async {
            if (_isLikeBusy) return;
            final previousLiked = _isLiked;
            final previousCount = _likeCount;
            final nextLiked = !previousLiked;
            setState(() {
              _isLikeBusy = true;
              _isLiked = nextLiked;
              _likeCount = (previousCount + (nextLiked ? 1 : -1)).clamp(0, 1 << 30);
            });
            try {
              final response = await BackendService.toggleLike(widget.post.id);
              if (!response.success) throw response.error ?? "Failed";
              
              // Trust the toggle response - no extra API call needed
              // The optimistic update already set the UI state
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _isLiked = previousLiked;
                _likeCount = previousCount;
              });
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            } finally {
              if (mounted) {
                setState(() {
                  _isLikeBusy = false;
                });
              }
            }
          },
          color: isLiked ? Colors.red : Colors.white,
        );
      },
    );
  }

  Widget _buildCommentButton() {
    return _actionButton(
      Icons.mode_comment_outlined,
      widget.post.commentCount.toString(),
      () {
        setState(() {
          _showComments = true;
        });
        _videoController?.pause();
      },
    );
  }

  Widget _buildShareButton() {
    return _actionButton(
      Icons.share_outlined,
      'Share',
      () {
        // TODO: Implement share functionality
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share feature coming soon!')),
        );
      },
    );
  }

  Widget _buildFollowButton() {
    final user = AuthService.currentUser;
    if (user == null || user.uid == widget.post.authorId) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: _isFollowedFuture,
      builder: (context, snapshot) {
        if (!_isFollowBusy && snapshot.hasData && _cachedIsFollowed == null) {
          _cachedIsFollowed = snapshot.data;
          _isFollowed = snapshot.data ?? _isFollowed;
        }
        // Use cached value if available
        final isFollowed = _cachedIsFollowed ?? _isFollowed;
        return _actionButton(
          isFollowed ? Icons.person_remove_outlined : Icons.person_add_outlined,
          isFollowed ? 'Unfollow' : 'Follow',
          () async {
            if (_isFollowBusy) return;
            final previous = _isFollowed;
            setState(() {
              _isFollowBusy = true;
              _isFollowed = !previous;
            });
            try {
              final response = await BackendService.toggleFollow(widget.post.authorId);
              if (!response.success) throw response.error ?? "Failed";
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _isFollowed = previous;
              });
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            } finally {
              if (mounted) {
                setState(() {
                  _isFollowBusy = false;
                });
              }
            }
          },
          color: isFollowed ? Colors.white : const Color(0xFF4C5EFF),
        );
      },
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              color: color ?? Colors.white,
              size: 32,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList(ScrollController scrollController) {
    return FutureBuilder<List<Comment>>(
      future: _commentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _cachedComments == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final comments = snapshot.data ?? _cachedComments ?? [];
        
        if (comments.isEmpty) {
          return const Center(
            child: Text('No comments yet. Be the first!'),
          );
        }

        return ListView.builder(
          controller: scrollController,
          itemCount: comments.length,
          itemBuilder: (context, index) {
            final comment = comments[index];
            return ListTile(
              leading: UserAvatar(
                imageUrl: comment.authorProfileImage,
                name: comment.authorName,
                radius: 18,
              ),
              title: Text(
                comment.authorName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(comment.text),
            );
          },
        );
      },
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentController,
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF4C5EFF),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () async {
                  final text = _commentController.text.trim();
                  final user = AuthService.currentUser;

                  if (text.isNotEmpty && user != null) {
                    _commentController.clear();
                    FocusScope.of(context).unfocus();

                    final response = await BackendService.addComment(widget.post.id, text);
                    if (!response.success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${response.error}')),
                      );
                    } else if (mounted) {
                      // Refresh comments after adding new one
                      setState(() {
                        _cachedComments = null;
                        _commentsFuture = CommentService.getComments(widget.post.id)
                          ..then((value) => _cachedComments = value);
                      });
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
