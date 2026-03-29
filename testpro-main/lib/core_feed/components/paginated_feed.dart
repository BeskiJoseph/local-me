import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../controllers/feed_controller.dart';
import 'post_card.dart';

/// A reusable, dumb list component for the new core_feed architecture.
/// 🚀 UNIVERSAL: Now accepts any FeedController provider (Home, Profile, Global).
class PaginatedFeed extends ConsumerStatefulWidget {
  final StateNotifierProvider<FeedController, FeedState> controllerProvider;
  
  const PaginatedFeed({
    super.key, 
    required this.controllerProvider,
  });

  @override
  ConsumerState<PaginatedFeed> createState() => _PaginatedFeedState();
}

class _PaginatedFeedState extends ConsumerState<PaginatedFeed> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 🧠 INITIAL LOAD: Auto-trigger the discovery engine on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(widget.controllerProvider.notifier).loadInitialPosts();
    });

    // 🧠 PAGINATION TRIGGER: Detect end-of-scroll and call the Brain
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        ref.read(widget.controllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🧠 BRAIN CONNECTION: Watch the passed controller state
    final feedState = ref.watch(widget.controllerProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(widget.controllerProvider.notifier).loadInitialPosts(),
      child: ListView.builder(
        controller: _scrollController,
        // Ensure the list is always scrollable for Pull-to-Refresh
        physics: const AlwaysScrollableScrollPhysics(), 
        itemCount: feedState.postIds.length + (feedState.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          // LOADING INDICATOR AT BOTTOM
          if (index == feedState.postIds.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                   width: 24,
                   height: 24,
                   child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final postId = feedState.postIds[index];
          // ✨ RENDER DUMB CARD: Pass only the ID to allow the card to watch its own data
          return PostCard(key: ValueKey(postId), postId: postId);
        },
      ),
    );
  }
}
