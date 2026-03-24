// Phase 2: Refactor post action row to use global PostStore (no local state)
// This file now relies on Riverpod's providers for a single source of truth.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/post_state.dart';

// A minimal action row showing like button and counters.
// Expects a postId to read the post from the global store.
class PostActionRow extends ConsumerWidget {
  final String postId;
  const PostActionRow({Key? key, required this.postId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    final store = ref.read(postStoreProvider.notifier);
    final isLiked = post?.isLiked ?? false;
    final likeCount = post?.likeCount ?? 0;
    final commentCount = post?.commentCount ?? 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        IconButton(
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.red : null,
          ),
          onPressed: () {
            // Optimistic update via global store
            store.toggleLike(postId);
          },
        ),
        Text('$likeCount'),
        SizedBox(width: 16),
        Icon(Icons.comment),
        SizedBox(width: 6),
        Text('$commentCount'),
      ],
    );
  }
}
