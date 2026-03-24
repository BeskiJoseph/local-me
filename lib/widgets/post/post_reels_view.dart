import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/post_state.dart';
import './post_card.dart';

class PostReelsView extends ConsumerWidget {
  const PostReelsView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postIds = ref.watch(postStoreProvider.select((s) => s.postIds));
    return ListView.builder(
      itemCount: postIds.length,
      itemBuilder: (context, index) {
        final id = postIds[index];
        return PostCard(postId: id);
      },
    );
  }
}
