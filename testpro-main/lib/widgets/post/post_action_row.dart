import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/social_service.dart';
import '../../services/backend_service.dart';
import '../../screens/post_detail_screen.dart';

class PostActionRow extends StatefulWidget {
  final Post post;
  final String? currentUserId;
  final Stream<bool>? isLikedStream;
  final Future<bool> Function(String)? onLikeToggle;

  const PostActionRow({
    super.key,
    required this.post,
    this.currentUserId,
    this.isLikedStream,
    this.onLikeToggle,
  });

  @override
  State<PostActionRow> createState() => _PostActionRowState();
}

class _PostActionRowState extends State<PostActionRow> {
  bool _liked = false;
  int _likeCount = 0;
  bool _isLikeBusy = false;
  bool? _optimisticLiked;
  int? _optimisticLikeCount;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
  }

  void _toggleLike(String userId, bool streamLiked, int streamCount) {
    if (_isLikeBusy) return;
    final bool currentOptimistic = _optimisticLiked ?? streamLiked;
    final bool newTarget = !currentOptimistic;

    final int newCount;
    if (newTarget == streamLiked) {
      newCount = streamCount;
    } else if (newTarget) {
      newCount = streamCount + 1;
    } else {
      newCount = streamCount > 0 ? streamCount - 1 : 0;
    }

    setState(() {
      _isLikeBusy = true;
      _optimisticLiked = newTarget;
      _optimisticLikeCount = newCount;
    });

    final toggleFuture = widget.onLikeToggle != null
        ? widget.onLikeToggle!(widget.post.id)
        : BackendService.toggleLike(widget.post.id);

    toggleFuture.then((response) {
      final bool success = response is bool ? response : (response as dynamic).success;
      if (!mounted) return;
      if (success) {
        setState(() {
          _liked = newTarget;
          _likeCount = _optimisticLikeCount ?? _likeCount;
          _optimisticLiked = null;
          _optimisticLikeCount = null;
          _isLikeBusy = false;
        });
      } else {
        setState(() {
          _optimisticLiked = null;
          _optimisticLikeCount = null;
          _isLikeBusy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action failed. Check connection.")),
        );
      }
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _optimisticLiked = null;
        _optimisticLikeCount = null;
        _isLikeBusy = false;
      });
    });
  }

  @override
  void dispose() => super.dispose();

  @override
  Widget build(BuildContext context) {
    // Dependency Injection: Use provided props or fallback to global services
    final userId = widget.currentUserId ?? AuthService.currentUser?.uid;
    final stream = widget.isLikedStream ??
        (userId != null
            ? SocialService.isPostLikedStream(widget.post.id, userId)
            : Stream.value(widget.post.isLiked));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: StreamBuilder<bool>(
        stream: stream,
        initialData: widget.post.isLiked,
        builder: (context, snapshot) {
          final streamLiked = snapshot.data ?? widget.post.isLiked;
          final streamCount = widget.post.likeCount;

          if (!_isLikeBusy && snapshot.hasData) {
            _liked = snapshot.data ?? _liked;
          }

          final isLiked = _optimisticLiked ?? _liked;
          final displayCount = _optimisticLikeCount ?? _likeCount;

          return Row(
            children: [
              // Like Action
              InkWell(
                onTap: userId == null
                    ? null
                    : () => _toggleLike(userId, streamLiked, streamCount),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 20,
                        color: isLiked
                            ? const Color(0xFF00B87C)
                            : const Color(0xFF8E8E93),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLiked ? 'Useful' : 'Useful',
                        style: TextStyle(
                          color: isLiked
                              ? const Color(0xFF00B87C)
                              : const Color(0xFF3A3A3C),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                      if (displayCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          displayCount.toString(),
                          style: TextStyle(
                            color: isLiked 
                                ? const Color(0xFF00B87C) 
                                : const Color(0xFF8E8E93),
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Comment Action
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(post: widget.post),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 22,
                        color: Color(0xFF8E8E93),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.post.commentCount.toString(),
                        style: const TextStyle(
                          color: Color(0xFF3A3A3C),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Replies',
                        style: TextStyle(
                          color: Color(0xFF3A3A3C),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
