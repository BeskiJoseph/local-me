import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../services/auth_service.dart';
import '../utils/proxy_helper.dart';
import 'personal_account.dart';

import '../models/post.dart';
import '../models/comment.dart';
import '../services/backend_service.dart';
import '../services/post_service.dart';
import '../config/app_theme.dart';
import '../core/utils/time_utils.dart';
import '../core/utils/navigation_utils.dart';
import '../shared/widgets/user_avatar.dart';
import '../core/session/user_session.dart';
import '../services/socket_service.dart';
import '../models/api_response.dart';

class PostDetailScreen extends StatefulWidget {
  final Post? post;
  final String? postId;

  const PostDetailScreen({super.key, this.post, this.postId})
      : assert(post != null || postId != null);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  Post? _post;
  bool _isLoading = false;
  bool? _optimisticLiked;
  bool? _optimisticSubscribed;
  int? _optimisticLikeCount;
  final TextEditingController _commentController = TextEditingController();

  // REST States
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isFollowed = false;
  List<Comment> _comments = [];
  bool _isLoadingComments = false;
  bool _isTogglingLike = false;
  bool _isTogglingFollow = false;
  StreamSubscription? _postEventSubscription;
  
  void _navigateToUserProfile(String userId) {
    NavigationUtils.navigateToProfile(context, userId);
  }

  @override
  void initState() {
    super.initState();
    if (widget.post != null) {
      _post = widget.post;
      _likeCount = _post!.likeCount;
      _initializeVideo();
      _loadAllStatus();
      SocketService.joinPost(_post!.id);
    } else {
      _loadPost();
    }
    
    // Global Event Sync
    _postEventSubscription = PostService.events.listen((event) {
      if (!mounted || _post == null) return;
      
      if (event.type == FeedEventType.postLiked && event.data['postId'] == _post!.id) {
        setState(() {
          _isLiked = event.data['isLiked'];
          _likeCount = event.data['likeCount'];
          _optimisticLiked = null;
          _optimisticLikeCount = null;
        });
      } else if (event.type == FeedEventType.userFollowed && event.data['userId'] == _post!.authorId) {
        setState(() {
          _isFollowed = event.data['isFollowing'];
          _optimisticSubscribed = null;
        });
      }
    });
  }

  Future<void> _loadAllStatus() async {
    if (_post == null) return;
    
    setState(() => _isLoadingComments = true);
    
    final user = AuthService.currentUser;
    final shouldCheckFollow = user != null && user.uid != _post!.authorId;

    try {
      final results = await Future.wait([
        BackendService.checkLikeState(_post!.id),
        shouldCheckFollow ? BackendService.checkFollowState(_post!.authorId) : Future.value(null),
        BackendService.getComments(_post!.id, limit: 10),
      ]);

      if (!mounted) return;

      final likeResp = results[0] as ApiResponse<Map<String, dynamic>>;
      final followResult = results[1];
      final followResp = followResult is ApiResponse<bool> ? followResult : null;
      final commentsResp = results[2] as ApiResponse<List<dynamic>>;

      setState(() {
        if (likeResp.success && likeResp.data != null) {
          final data = likeResp.data!;
          _isLiked = data['liked'] == true;
          _likeCount = (data['likeCount'] as num?)?.toInt() ?? _post!.likeCount;
        }
        if (followResp != null && followResp.success) {
          _isFollowed = followResp.data ?? false;
        }
        if (commentsResp.success && commentsResp.data != null) {
          _comments = commentsResp.data!.map<Comment>((json) => Comment.fromJson(json)).toList();
        }
        _isLoadingComments = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingComments = false);
    }
  }

  Future<void> _loadPost() async {
    setState(() => _isLoading = true);
    try {
      final response = await BackendService.getPost(widget.postId!);
      if (response.success && response.data != null) {
        setState(() {
          _post = Post.fromJson(response.data!);
          _likeCount = _post!.likeCount;
          _isLoading = false;
        });
        _initializeVideo();
        _loadAllStatus();
        SocketService.joinPost(_post!.id);
        // Track post view
        BackendService.trackPostView(widget.postId!).catchError((e) {
          if (kDebugMode) debugPrint('Error tracking view: $e');
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (kDebugMode) debugPrint('Error loading post: $e');
    }
  }

  void _initializeVideo() {
    if (_post == null) return;
    _isVideo = _post!.mediaType == 'video' &&
        _post!.mediaUrl != null &&
        _post!.mediaUrl!.isNotEmpty;
    if (_isVideo) {
      _videoController = VideoPlayerController.network(ProxyHelper.getUrl(_post!.mediaUrl!))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        })
        ..setLooping(true);
    }
  }

  @override
  void dispose() {
    if (_post != null) {
      SocketService.leavePost(_post!.id);
    }
    _postEventSubscription?.cancel();
    _videoController?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_post == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text("Post not found")),
      );
    }

    final post = _post!;
    final int commentsCount = post.commentCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          post.title.isNotEmpty ? post.title : 'Post Details',
          style: const TextStyle(
            color: Color(0xFF1C1C1E),
            fontWeight: FontWeight.w700,
            fontSize: 17,
            fontFamily: 'Inter',
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF1C1C1E)),
            onPressed: () => _showPostOptions(context, AuthService.currentUser),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author Section - Modern Design
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: ValueListenableBuilder(
                      valueListenable: UserSession.current,
                      builder: (context, sessionData, _) {
                        final isMe = UserSession.isMe(post.authorId);
                        final displayAvatar = isMe ? (sessionData?.avatarUrl ?? post.authorProfileImage) : post.authorProfileImage;
                        final displayName = isMe 
                            ? (sessionData?.displayName ?? post.authorName) 
                            : ((post.authorName.isEmpty || post.authorName == 'User') ? 'User' : post.authorName);
                            
                        return InkWell(
                          onTap: () => _navigateToUserProfile(post.authorId),
                          child: Row(
                            children: [
                              // Avatar with gradient border
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                  ),
                                ),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF667EEA),
                                    shape: BoxShape.circle,
                                    image: displayAvatar != null
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(ProxyHelper.getUrl(displayAvatar)),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: displayAvatar == null
                                      ? Text(
                                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 18,
                                            fontFamily: 'Inter',
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Color(0xFF1C1C1E),
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    const SizedBox(height: 2),
                                    Text(
                                      post.scope.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF8E8E93),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildSubscribeButtonSmall(),
                            ],
                          ),
                        );
                      }
                    ),
                  ),

                  // Media Section
                  if (post.mediaUrl != null)
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          // Instagram-style: 4:5 for images, 9:16 for videos
                          aspectRatio: post.mediaType == 'video' ? 9 / 16 : 4 / 5,
                          child: _isVideo && _videoController != null
                              ? Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_videoController!),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.2),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _videoController!.value.isPlaying
                                            ? Icons.pause_circle_filled_rounded
                                            : Icons.play_circle_filled_rounded,
                                        size: 64,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          if (_videoController!.value.isPlaying) {
                                            _videoController!.pause();
                                          } else {
                                            _videoController!.play();
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                )
                              : Image.network(
                                  ProxyHelper.getUrl(post.mediaUrl!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade100,
                                      child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 40)),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (post.title.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              post.title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1C1C1E),
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            _buildModernLikeButton(),
                            const SizedBox(width: 16),
                            _modernActionButton(Icons.ios_share_rounded, 'Share', () {}),
                            const Spacer(),
                            _modernActionButton(Icons.outlined_flag_rounded, 'Report', () {}),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Comments Section Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      children: [
                        const Text(
                          "Replies",
                          style: TextStyle(
                            fontWeight: FontWeight.w800, 
                            fontSize: 18,
                            color: Color(0xFF1C1C1E),
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            commentsCount.toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCommentsList(),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    if (_post == null) return const SizedBox.shrink();
    if (_isLoadingComments) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text("No comments yet. Be the first!")),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _comments.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final comment = _comments[index];
        return ValueListenableBuilder(
          valueListenable: UserSession.current,
          builder: (context, sessionData, _) {
            final isMe = UserSession.isMe(comment.authorId);
            final displayAvatar = isMe ? (sessionData?.avatarUrl ?? comment.authorProfileImage) : comment.authorProfileImage;
            final displayName = isMe 
                ? (sessionData?.displayName ?? comment.authorName) 
                : ((comment.authorName.isEmpty || comment.authorName == 'User') ? 'User' : comment.authorName);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _navigateToUserProfile(comment.authorId),
                    child: UserAvatar(
                      imageUrl: displayAvatar,
                      name: displayName,
                      radius: 18,
                      backgroundColor: const Color(0xFFE5E7EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF1C1C1E),
                                fontFamily: 'Inter',
                              ),
                            ),
                            Text(
                              _formatDate(comment.createdAt),
                              style: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 11,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          comment.text,
                          style: const TextStyle(
                            color: Color(0xFF3A3A3C),
                            fontSize: 14,
                            height: 1.4,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }
  
  String _formatDate(DateTime date) => TimeUtils.formatDate(date);

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  hintText: "Add a comment...",
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                ),
                style: const TextStyle(fontSize: 14, fontFamily: 'Inter'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              final text = _commentController.text.trim();
              final user = AuthService.currentUser;
              
              if (text.isNotEmpty && user != null) {
                 _commentController.clear();
                 FocusScope.of(context).unfocus();

                 // --- Optimistic UI ---
                 final optimistic = Comment(
                    id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
                    postId: _post!.id,
                    authorId: user.uid,
                    authorName: user.displayName ?? 'You',
                    authorProfileImage: user.photoURL,
                    text: text,
                    createdAt: DateTime.now(),
                 );

                 setState(() {
                   _comments.insert(0, optimistic);
                 });

                 try {
                   final response = await BackendService.addComment(_post!.id, text);
                   if (response.success && response.data != null) {
                     final realComment = Comment.fromJson(response.data!);
                     if (mounted) {
                       setState(() {
                         final idx = _comments.indexWhere((c) => c.id == optimistic.id);
                         if (idx != -1) _comments[idx] = realComment;
                       });
                     }
                   } else {
                     throw Exception(response.error);
                   }
                 } catch (e) {
                   if (mounted) {
                     setState(() {
                       _comments.removeWhere((c) => c.id == optimistic.id);
                     });
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Comment failed: $e')));
                   }
                 }
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF2563EB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF8E8E93)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF3A3A3C),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernLikeButton() {
    final user = AuthService.currentUser;
    final isLiked = _optimisticLiked ?? _isLiked;
    final displayLikeCount = _optimisticLikeCount ?? _likeCount;

    return InkWell(
      onTap: () async {
        if (_isTogglingLike) return;
        if (user == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please login to like")));
          return;
        }
        _isTogglingLike = true;
        final bool currentLiked = _optimisticLiked ?? _isLiked;
        final newTarget = !currentLiked;
        setState(() {
          _optimisticLiked = newTarget;
          _optimisticLikeCount = displayLikeCount + (newTarget ? 1 : -1);
        });
        try {
          final response = await BackendService.toggleLike(_post!.id);
          if (response.success) {
            // Emit to sync other instances of this post card/screen
            PostService.emit(FeedEvent(FeedEventType.postLiked, {
              'postId': _post!.id,
              'isLiked': newTarget,
              'likeCount': _optimisticLikeCount ?? displayLikeCount,
            }));
          } else {
            throw response.error ?? "Failed";
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _optimisticLiked = null;
              _optimisticLikeCount = null;
            });
          }
        } finally {
          if (mounted) {
            setState(() => _isTogglingLike = false);
          }
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 20,
              color: isLiked ? const Color(0xFFE53935) : const Color(0xFF8E8E93),
            ),
            const SizedBox(width: 6),
            Text(
              displayLikeCount > 0 ? '$displayLikeCount Liked' : 'Like',
              style: TextStyle(
                color: isLiked ? const Color(0xFFE53935) : const Color(0xFF3A3A3C),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscribeButtonSmall() {
    final user = AuthService.currentUser;
    if (user == null || _post == null || user.uid == _post!.authorId) return const SizedBox.shrink();

    final isSubscribed = _optimisticSubscribed ?? _isFollowed;

    return GestureDetector(
      onTap: () async {
        if (_isTogglingFollow) return;
        final bool current = _optimisticSubscribed ?? _isFollowed;
        _isTogglingFollow = true;
        setState(() => _optimisticSubscribed = !current);
        try {
          final response = await BackendService.toggleFollow(_post!.authorId);
          if (response.success) {
            // Emit to sync
            PostService.emit(FeedEvent(FeedEventType.userFollowed, {
              'userId': _post!.authorId,
              'isFollowing': !current,
            }));
          }
          setState(() => _optimisticSubscribed = null);
        } catch (e) {
          if (mounted) setState(() => _optimisticSubscribed = null);
        } finally {
          if (mounted) {
            setState(() => _isTogglingFollow = false);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSubscribed ? const Color(0xFFF3F4F6) : const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          isSubscribed ? 'Following' : 'Follow',
          style: TextStyle(
            color: isSubscribed ? const Color(0xFF6B7280) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }




  void _showPostOptions(BuildContext context, dynamic user) {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to manage posts')),
      );
      return;
    }

    final bool isAuthor = user.uid == _post!.authorId;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              if (isAuthor)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Post', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context); // Close sheet
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Post?'),
                        content: const Text('This action cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                             child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                             child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      try {
                        await PostService.deletePost(_post!.id);
                        if (mounted) {
                          Navigator.pop(context, true); // Pop Detail Screen with refresh signal
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Post deleted')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    }
                  },
                ),
              if (!isAuthor)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report Post'),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Post reported. Thank you.')),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
