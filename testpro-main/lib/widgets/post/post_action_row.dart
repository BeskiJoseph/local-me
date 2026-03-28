import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../comments_bottom_sheet.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/services/interaction_service.dart';
import 'package:testpro/utils/debounce.dart';

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
  bool _isLikeBusy = false;

  void _toggleLike(String userId, Post latestPost) async {
    if (_isLikeBusy) return;

    Debounce.run('like_${latestPost.id}', () async {
      setState(() => _isLikeBusy = true);
      
      await InteractionService.toggleLike(
        postId: latestPost.id,
        ref: ref,
        onBusy: () => setState(() => _isLikeBusy = true),
        onReady: () => setState(() => _isLikeBusy = false),
      );
    });
  }

  @override
  void dispose() {
    Debounce.cancel('like_${widget.post.id}');
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
