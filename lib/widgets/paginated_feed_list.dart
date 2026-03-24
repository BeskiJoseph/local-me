import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import './post/post_card.dart';
import '../core/state/post_state.dart';

class PaginatedFeedList extends ConsumerWidget {
  const PaginatedFeedList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postIds = ref.watch(postStoreProvider.select((s) => s.postIds));

    return ListView.builder(
      cacheExtent: 500,
      itemCount: postIds.length,
      itemBuilder: (_, index) {
        return PostCard(postId: postIds[index]);
      },
    );
  }
}
