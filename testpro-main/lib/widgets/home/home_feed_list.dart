import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:testpro/core/state/post_state.dart';
import '../../models/post.dart';
import '../../config/app_theme.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';
import '../../screens/post_reels_view.dart';
import '../feed/paginated_feed_list.dart';

/// Feed list — owned by Riverpod PostStoreNotifier.
/// Uses AutomaticKeepAliveClientMixin to preserve scroll position.
///
/// BUG-015/030 FIXED: Eradicated static arrays and futures.
class HomeFeedList extends ConsumerStatefulWidget {
  final String feedType;
  final String? userCity;
  final String? userCountry;
  final bool isLoadingLocation;
  final String? locationError;
  final VoidCallback onRetryLocation;
  final String searchQuery;

  const HomeFeedList({
    super.key,
    required this.feedType,
    required this.userCity,
    required this.userCountry,
    required this.isLoadingLocation,
    required this.locationError,
    required this.onRetryLocation,
    required this.searchQuery,
  });

  @override
  ConsumerState<HomeFeedList> createState() => _HomeFeedListState();

  /// 🔥 Add new post to feed via Riverpod store immediately
  static void addNewPost(Post post, WidgetRef ref, {String? feedType}) {
    // Just delegate to PaginatedFeedList's method or direct Store call
    PaginatedFeedList.addNewPost(post, ref, feedType: feedType ?? 'local');
  }
}

class _HomeFeedListState extends ConsumerState<HomeFeedList>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoadingLocation) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (widget.locationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                widget.locationError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: widget.onRetryLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (widget.feedType == 'local' && widget.userCity == null) {
      return const Center(child: Text('Waiting for location...'));
    }

    return PaginatedFeedList(
      feedType: widget.feedType,
      userCity: widget.userCity,
      userCountry: widget.userCountry,
      // We pass down a custom builder so we can filter locally by searchQuery
      // and render EventPostCard vs NextdoorStylePostCard accurately.
      itemBuilder: (context, post, index, isCurrent) {
        // Local Filter Logic
        if (post.isEvent && post.computedStatus == 'archived') return const SizedBox.shrink();
        
        if (widget.searchQuery.isNotEmpty) {
          final q = widget.searchQuery.toLowerCase();
          final matches = post.title.toLowerCase().contains(q) ||
                post.body.toLowerCase().contains(q) ||
                post.authorName.toLowerCase().contains(q) ||
                post.category.toLowerCase().contains(q);
          if (!matches) return const SizedBox.shrink();
        }

        if (post.isEvent || post.category.toLowerCase() == 'events') {
          return EventPostCard(post: post);
        }

        return NextdoorStylePostCard(
          post: post,
          currentCity: widget.userCity,
          onTap: () {
             Navigator.push(
               context,
               MaterialPageRoute(
                 builder: (_) => PostReelsView(
                   posts: const [], // PostReelsView handles fetching from Riverpod now 
                   startIndex: index,
                   feedType: widget.feedType,
                   initialHasMore: true,
                 ),
               ),
             );
          },
        );
      },
      onRefresh: () async {
         // Reload via store
         await ref.read(postStoreProvider.notifier).loadMore(
           feedType: widget.feedType,
           latitude: null, // the PaginatedFeedList internal logic will attach LocationService coordinates
           longitude: null,
         );
      },
    );
  }
}
