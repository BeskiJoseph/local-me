import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../core/state/post_state.dart';
import '../nextdoor_post_card.dart';

class PostCard extends ConsumerStatefulWidget {
  final String postId;
  const PostCard({super.key, required this.postId});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    if (post == null) return const SizedBox.shrink();
    
    return NextdoorStylePostCard(post: post);
  }
}
