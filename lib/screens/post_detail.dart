import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/state/post_state.dart';
import '../widgets/post/post_card.dart';
import '../widgets/post/post_action_row.dart';

class PostDetailScreen extends ConsumerWidget {
  final String postId;
  const PostDetailScreen({Key? key, required this.postId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(postId));
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Post Detail')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Post Detail')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.content, style: TextStyle(fontSize: 18.0)),
            SizedBox(height: 12.0),
            PostActionRow(postId: postId),
            SizedBox(height: 6.0),
            Text(
              '${post.commentCount} comments',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
