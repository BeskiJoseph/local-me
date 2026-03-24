import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/post_state.dart';
import './post_action_row.dart';

class PostCard extends ConsumerStatefulWidget {
  final String postId;

  const PostCard({super.key, required this.postId});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(postStoreProvider.notifier).markVisible(widget.postId);
    });
  }

  @override
  void dispose() {
    ref.read(postStoreProvider.notifier).markInvisible(widget.postId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    if (post == null) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 100.0,
            color: Colors.grey.shade300,
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.content, style: const TextStyle(fontSize: 16.0)),
            const SizedBox(height: 8.0),
            PostActionRow(postId: widget.postId),
            const SizedBox(height: 6.0),
            Text(
              '${post.commentCount} comments',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
