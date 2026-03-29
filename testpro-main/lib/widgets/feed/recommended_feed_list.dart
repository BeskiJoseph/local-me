import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/interest_picker_screen.dart';
import '../../screens/post_reels_view.dart';
import '../feed/paginated_feed_list.dart';

/// A specialized widget to handle the personalized recommendation feed
/// BUG-031 FIXED: Removed PostLoaderMixin and local state in favor of PaginatedFeedList & Riverpod.
class RecommendedFeedList extends ConsumerStatefulWidget {
  const RecommendedFeedList({super.key});

  @override
  ConsumerState<RecommendedFeedList> createState() =>
      _RecommendedFeedListState();
}

class _RecommendedFeedListState extends ConsumerState<RecommendedFeedList>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final store = ref.watch(postStoreProvider);
    final feedType = 'recommended';
    
    // Check if feed empty and loaded
    final postIds = store.postIdsByFeedType[feedType] ?? [];
    final isLoading = store.isLoadingByFeedType[feedType] ?? false;
    
    if (postIds.isEmpty && !isLoading && store.hasMoreByFeedType[feedType] == false) {
      return _buildEmptyState();
    }

    return PaginatedFeedList(
      feedType: feedType,
      itemBuilder: (context, post, index, isCurrent) {
        // Hide archived events
        if (post.isEvent && post.computedStatus == 'archived') {
          return const SizedBox.shrink();
        }

        // Route events to EventPostCard
        if (post.isEvent || post.category.toLowerCase() == 'events') {
          return EventPostCard(post: post);
        }

        return NextdoorStylePostCard(
          post: post,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PostReelsView(
                  posts: const [], // Delegated to Riverpod
                  startIndex: index,
                  feedType: feedType,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('No recommendations yet. Interact more!'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const InterestPickerScreen(),
                ),
              );
            },
            child: const Text('Pick Interests'),
          ),
        ],
      ),
    );
  }
}
