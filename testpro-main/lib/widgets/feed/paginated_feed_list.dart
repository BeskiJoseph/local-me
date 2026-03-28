import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../core/state/post_state.dart';
import '../post/post_card.dart';
import '../../services/location_service.dart';
import '../../config/feed_constants.dart';


enum FeedLayoutType { list, paged }

class PaginatedFeedList extends ConsumerStatefulWidget {
  final String? feedType;
  final String? authorId;
  final String? userCity;
  final String? userCountry;
  final int pageSize;
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onLoadMore;
  final FeedLayoutType layoutType;
  final int startIndex;
  final String? postId;
  final String? mediaType;
  final List<Post>? initialPosts;
  final bool initialHasMore;
  final Widget Function(
    BuildContext context,
    Post post,
    int index,
    bool isCurrent,
  )?
  itemBuilder;

  const PaginatedFeedList({
    super.key,
    this.feedType,
    this.authorId,
    this.mediaType,
    this.userCity,
    this.userCountry,
    this.pageSize = FeedConstants.defaultPageSize,
    this.onRefresh,
    this.onLoadMore,
    this.layoutType = FeedLayoutType.list,
    this.startIndex = 0,
    this.postId,
    this.initialPosts,
    this.initialHasMore = true,
    this.itemBuilder,
  });

  @override
  ConsumerState<PaginatedFeedList> createState() => _PaginatedFeedListState();

  /// 🔥 Static method to add new post to feed immediately
  static void addNewPost(Post post, WidgetRef ref, {String? feedType}) {
    debugPrint('➕ PaginatedFeedList.addNewPost: ${post.id}');
    // Register to store with prepend=true (new posts go first)
    // Use provided feedType or default to global
    final targetFeed = feedType ?? 'global';
    ref.read(postStoreProvider.notifier).registerPosts([post], forFeedType: targetFeed, prepend: true);
    // The ref.listen in the widget will pick up the change and rebuild
  }
}

class _PaginatedFeedListState extends ConsumerState<PaginatedFeedList> {
  final ScrollController _scrollController = ScrollController();
  PageController? _pageController;  // For paged layout
  late List<String> _displayIds;
  bool _isRefilling = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    
    // 🔥 CRITICAL FIX: Initialize _displayIds IMMEDIATELY with initialPosts
    if (widget.initialPosts?.isNotEmpty ?? false) {
      _displayIds = widget.initialPosts!.map((p) => p.id).toList();
      
      // 🔥 CRITICAL: Create PageController ONCE for paged layout
      if (widget.layoutType == FeedLayoutType.paged) {
        _pageController = PageController(initialPage: widget.startIndex);
      }
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(postStoreProvider.notifier)
            .registerPosts(
              widget.initialPosts!,
              forFeedType: widget.feedType ?? 'global',
              prepend: false,
            );
      });
    } else {
      _displayIds = [];
      if (widget.layoutType == FeedLayoutType.paged) {
        _pageController = PageController(initialPage: widget.startIndex);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDisplayIds();
        if (_displayIds.length < widget.pageSize) {
          _checkRefill();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController?.dispose();  // Dispose PageController
    super.dispose();
  }

  void _syncDisplayIds() {
    final store = ref.read(postStoreProvider);

    // 🔥 Get postIds for THIS specific feedType, not all posts
    final feedSpecificIds = widget.feedType != null
        ? (store.postIdsByFeedType[widget.feedType!] ?? [])
        : store.postIds;

    // 🔥 Find new IDs that aren't in _displayIds yet
    final currentIdSet = _displayIds.toSet();
    final newIds = feedSpecificIds.where((id) => !currentIdSet.contains(id)).toList();

    if (newIds.isNotEmpty) {
      if (kDebugMode) {
        print(
          '[PaginatedFeedList] Syncing ${widget.feedType}: adding ${newIds.length} new IDs',
        );
        print(
          '[PaginatedFeedList] feedSpecificIds total: ${feedSpecificIds.length}',
        );
      }
      setState(() {
        // 🔥 REBUILD _displayIds to match store order: add new IDs at BEGINNING
        _displayIds = [...newIds, ..._displayIds];
      });
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 600) {
      _triggerLoadMore();
    }
  }

  Future<void> _triggerLoadMore() async {
    if (widget.onLoadMore != null) {
      await widget.onLoadMore!();
    } else if (widget.feedType != null) {
      final pos = LocationService.currentPosition;
      await ref.read(postStoreProvider.notifier).loadMore(
        feedType: widget.feedType!,
        authorId: widget.authorId,
        mediaType: widget.mediaType,
        latitude: pos?.latitude,
        longitude: pos?.longitude,
      );
    }
  }

  Future<void> _checkRefill() async {
    if (_isRefilling || !mounted) return;

    setState(() => _isRefilling = true);
    try {
      final store = ref.read(postStoreProvider);
      final feedType = widget.feedType ?? 'global';
      final freshIds = widget.feedType != null
          ? (store.postIdsByFeedType[widget.feedType!] ?? [])
          : store.postIds;

      // CRITICAL FIX: If completely empty, trigger initial load IMMEDIATELY
      // Don't wait in the loop - this prevents the delay before first API call
      if (freshIds.isEmpty && _displayIds.isEmpty) {
        debugPrint('[PaginatedFeedList] >>> Initial load for $feedType - triggering immediately');
        final isCurrentlyLoading = store.isLoadingByFeedType[feedType] ?? store.isLoading;
        if (!isCurrentlyLoading) {
          await _triggerLoadMore();
        }
        return; // Exit after initial load, let ref.listen handle updates
      }

      // 🔥 For refill (already have some posts), use loop with conservative delays
      while (mounted) {
        final store = ref.read(postStoreProvider);
        final feedType = widget.feedType ?? 'global';
        final freshIds = widget.feedType != null
            ? (store.postIdsByFeedType[widget.feedType!] ?? [])
            : store.postIds;

        // STOP if we already know there are no more posts
        final hasMore = store.hasMoreByFeedType[feedType] ?? true;
        if (!hasMore) break;

        // STOP if the last request resulted in an error
        final hasError = store.errorByFeedType[feedType] != null;
        if (hasError) break;

        // STOP if we have enough posts
        if (freshIds.length >= widget.pageSize) break;

        // Avoid overlapping loadMore calls
        final isCurrentlyLoading = store.isLoadingByFeedType[feedType] ?? store.isLoading;
        if (isCurrentlyLoading) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        await _triggerLoadMore();
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (mounted) setState(() => _isRefilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(postStoreProvider);

    // 🔥 Watch feed-specific postIds if feedType is set
    ref.listen(
      postStoreProvider.select((s) {
        if (widget.feedType != null) {
          return s.postIdsByFeedType[widget.feedType!] ?? [];
        }
        return s.postIds;
      }),
      (prev, next) {
        _syncDisplayIds();
      },
    );

    // 🔥 Don't show loading if we have initialPosts - prevents flash
    final hasInitialPosts = widget.initialPosts != null && widget.initialPosts!.isNotEmpty;
    
    // 🔥 CRITICAL FIX: Check if feed is loading - check both feed-specific and global loading
    final isFeedLoading = store.isLoadingByFeedType[widget.feedType] ?? store.isLoading;
    
    // 🔥 CRITICAL FIX: Also check if we're in initial loading state (empty display with no data yet)
    final isInitiallyLoading = _displayIds.isEmpty && !hasInitialPosts && store.postIdsByFeedType[widget.feedType]?.isEmpty != false;
    
    // 🔥 Return empty container while loading - parent (HomeScreen) already shows FeedShimmer
    if ((isFeedLoading || isInitiallyLoading || _isRefilling) && _displayIds.isEmpty && !hasInitialPosts) {
      return const SizedBox.shrink();
    }

    // 🔥 CRITICAL FIX: If _displayIds is empty but we have initialPosts,
    // use initialPosts IDs to prevent "No posts" flash
    final effectiveDisplayIds = _displayIds.isEmpty && widget.initialPosts != null
        ? widget.initialPosts!.map((p) => p.id).toList()
        : _displayIds;

    if (effectiveDisplayIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No posts found'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => widget.onRefresh?.call(),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(postStoreProvider.notifier).clearSeen();
        if (widget.onRefresh != null) {
          await widget.onRefresh!();
        } else if (widget.feedType != null) {
          // If no custom refresh, trigger a standard loadMore for the feedType
          await ref
              .read(postStoreProvider.notifier)
              .loadMore(
                feedType: widget.feedType ?? 'global',
                mediaType: widget.mediaType,
                latitude: widget.feedType == 'local' ? LocationService.currentPosition?.latitude : null,
                longitude: widget.feedType == 'local' ? LocationService.currentPosition?.longitude : null,
              );

        }
      },
      child: widget.layoutType == FeedLayoutType.paged
          ? PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _pageController,  // 🔥 Use state controller, don't recreate
              itemCount: effectiveDisplayIds.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
                if (index >= effectiveDisplayIds.length - 2) _checkRefill();
              },
              itemBuilder: (context, index) {
                final postId = effectiveDisplayIds[index];
                if (widget.itemBuilder != null) {
                  final post = ref.watch(postStoreProvider).posts[postId];
                  if (post == null) return const SizedBox.shrink();
                  return widget.itemBuilder!(
                    context,
                    post,
                    index,
                    index == _currentPage,
                  );
                }
                return PostCard(
                  postId: postId,
                  feedType: widget.feedType,
                );

              },
            )
          : ListView.separated(
              controller: _scrollController,
              itemCount: _displayIds.length + (_isRefilling ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index >= _displayIds.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final postId = _displayIds[index];
                if (widget.itemBuilder != null) {
                  final post = ref.watch(postStoreProvider).posts[postId];
                  if (post == null) return const SizedBox.shrink();
                  return widget.itemBuilder!(context, post, index, false);
                }
                return PostCard(
                  postId: postId,
                  feedType: widget.feedType,
                );

              },
            ),
    );
  }
}
