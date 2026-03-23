import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/social_service.dart';
import '../../services/backend_service.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/utils/safe_error.dart';
import '../comments_bottom_sheet.dart';
import 'dart:async';

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
  StreamSubscription? _subscription;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
    
    // Sync with global post events for real-time consistency
    _subscription = FeedEventBus.events.listen((event) {
      if (!mounted) return;
      if (event.type == FeedEventType.postLiked) {
        final data = event.data as Map<String, dynamic>;
        if (data['postId'] == widget.post.id) {
          setState(() {
            _liked = data['isLiked'];
            _likeCount = data['likeCount'];
            _optimisticLiked = null;
            _optimisticLikeCount = null;
            _isLikeBusy = false;
          });
        }
      }
    });
  }

  void _toggleLike(String userId, bool streamLiked, int streamCount) {
    final bool currentOptimistic = _optimisticLiked ?? _liked;
    final bool newTarget = !currentOptimistic;

    final int newCount = _likeCount + (newTarget ? 1 : -1);

    // Instagram-level feedback
    if (newTarget) HapticService.medium();

    setState(() {
      _isLikeBusy = true;
      _optimisticLiked = newTarget;
      _optimisticLikeCount = newCount;
    });

    // YouTube-style Debounce (300ms)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final toggleFuture = widget.onLikeToggle != null
            ? widget.onLikeToggle!(widget.post.id)
            : BackendService.toggleLike(widget.post.id);

        final response = await toggleFuture;
        final bool success = response is bool ? response : (response as dynamic).success;

        if (!mounted) return;

        if (success) {
          setState(() {
            _liked = newTarget;
            _likeCount = newCount;
            _optimisticLiked = null;
            _optimisticLikeCount = null;
            _isLikeBusy = false;
          });

          // Emit global event to sync other widgets showing this post
          FeedEventBus.emit(FeedEvent(
            FeedEventType.postLiked, {
            'postId': widget.post.id,
            'isLiked': _liked,
            'likeCount': _likeCount,
          }));
        } else {
          _rollback();
          _showError("Action failed. Check connection.");
        }
      } catch (e) {
        _rollback();
        _showError("An error occurred.");
      }
    });
  }

  void _rollback() {
    if (!mounted) return;
    setState(() {
      _optimisticLiked = null;
      _optimisticLikeCount = null;
      _isLikeBusy = false;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dependency Injection: Use provided props or fallback to global services
    final userId = widget.currentUserId ?? AuthService.currentUser?.uid;
    final stream = widget.isLikedStream ?? Stream.value(widget.post.isLiked);

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
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: isLiked
                            ? const Color(0xFFE53935)
                            : const Color(0xFF8E8E93),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLiked ? 'Liked' : 'Like',
                        style: TextStyle(
                          color: isLiked
                              ? const Color(0xFFE53935)
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
                                ? const Color(0xFFE53935) 
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
                onTap: () => CommentsBottomSheet.show(context, widget.post),
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
