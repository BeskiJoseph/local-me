import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/backend_service.dart';
import 'package:testpro/utils/safe_error.dart';
import '../comments_bottom_sheet.dart';
import 'package:testpro/core/events/feed_events.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/services/haptic_service.dart';
import 'dart:async';

class PostActionRow extends ConsumerStatefulWidget {
  final Post post;
  final String? currentUserId;

  const PostActionRow({
    super.key,
    required this.post,
    this.currentUserId,
  });

  @override
  ConsumerState<PostActionRow> createState() => _PostActionRowState();
}

class _PostActionRowState extends ConsumerState<PostActionRow> {
  Timer? _debounceTimer;
  bool _isLikeBusy = false;

  void _toggleLike(String userId, Post latestPost) async {
    if (_isLikeBusy) return;

    final bool isLiked = latestPost.isLiked;
    final int likeCount = latestPost.likeCount;
    
    final bool newTarget = !isLiked;
    final int newCount = likeCount + (newTarget ? 1 : -1);

    if (newTarget) HapticService.medium();

    final int version = DateTime.now().millisecondsSinceEpoch;
    final String postId = latestPost.id;

    // 1. Optimistic Update in Global Store
    final notifier = ref.read(postStoreProvider.notifier);
    notifier.setActionVersion(postId, 'like', version);
    notifier.updatePostPartially(postId, {
      'isLiked': newTarget,
      'likeCount': newCount,
    });

    setState(() => _isLikeBusy = true);

    // 2. Debounced API Call
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final response = await BackendService.toggleLike(postId);
        
        if (!mounted) return;

        // 3. Stale Response Check (Race Condition Protection)
        final latestVersion = ref.read(postActionVersionProvider((postId, 'like')));
        if (latestVersion != version) {
          // A newer action has been started, ignore this result
          return;
        }

        if (!response.success) {
          _rollback(postId, isLiked, likeCount);
          _showError("Action failed. Check connection.");
        } else {
          // Success: Sync with server data if needed, or just clear busy state
          setState(() => _isLikeBusy = false);
          
          // Emit global event for any legacy listeners
          FeedEventBus.emit(FeedEvent(FeedEventType.postLiked, {
            'postId': postId,
            'isLiked': newTarget,
            'likeCount': newCount,
          }));
        }
      } catch (e) {
        if (mounted) {
          _rollback(postId, isLiked, likeCount);
          _showError("An error occurred.");
        }
      } finally {
        if (mounted) setState(() => _isLikeBusy = false);
      }
    });
  }

  void _rollback(String postId, bool originalLiked, int originalCount) {
    ref.read(postStoreProvider.notifier).updatePostPartially(postId, {
      'isLiked': originalLiked,
      'likeCount': originalCount,
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
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.currentUserId ?? AuthService.currentUser?.uid;
    
    // 🔥 Reactive Subscription: Watch the specific post state in the store
    final post = ref.watch(postProvider(widget.post.id)) ?? widget.post;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Like Action
          InkWell(
            onTap: userId == null ? null : () => _toggleLike(userId, post),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    post.isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: post.isLiked
                        ? const Color(0xFFE53935)
                        : const Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    post.isLiked ? 'Liked' : 'Like',
                    style: TextStyle(
                      color: post.isLiked
                          ? const Color(0xFFE53935)
                          : const Color(0xFF3A3A3C),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      fontFamily: 'Inter',
                    ),
                  ),
                  if (post.likeCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      post.likeCount.toString(),
                      style: TextStyle(
                        color: post.isLiked 
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
            onTap: () => CommentsBottomSheet.show(context, post),
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
                    post.commentCount.toString(),
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
      ),
    );
  }
}
