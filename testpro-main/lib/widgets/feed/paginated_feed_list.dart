import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/post_state.dart';
import '../../models/post.dart';
import '../post/post_card.dart';

enum FeedLayoutType { list, paged }

typedef FeedItemBuilder = Widget Function(
  BuildContext context,
  Post post,
  int index,
  bool isCurrent,
);

class PaginatedFeedList extends ConsumerWidget {
  final String? feedType;
  final String? userCity;
  final String? userCountry;
  final FeedLayoutType layoutType;
  final String? mediaType;
  final List<Post>? initialPosts;
  final int startIndex;
  final bool initialHasMore;
  final FeedItemBuilder? itemBuilder;

  const PaginatedFeedList({
    super.key,
    this.feedType,
    this.userCity,
    this.userCountry,
    this.layoutType = FeedLayoutType.list,
    this.mediaType,
    this.initialPosts,
    this.startIndex = 0,
    this.initialHasMore = true,
    this.itemBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🔥 Single Source: Watch postIds from global store
    final postIds = ref.watch(postStoreProvider.select((s) => s.postIds));

    if (postIds.isEmpty) {
      return const Center(child: Text('No posts yet'));
    }

    if (layoutType == FeedLayoutType.paged) {
      return PageView.builder(
        scrollDirection: Axis.vertical,
        controller: PageController(initialPage: startIndex),
        itemCount: postIds.length,
        itemBuilder: (context, index) {
          return PostCard(postId: postIds[index]);
        },
      );
    }

    return ListView.builder(
      cacheExtent: 500,
      itemCount: postIds.length,
      itemBuilder: (context, index) {
        return PostCard(postId: postIds[index]);
      },
    );
  }
}
