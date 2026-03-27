import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../core/state/post_state.dart';
import '../post/post_card.dart';
import '../../services/location_service.dart';


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
    this.pageSize = 15,
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
}

class _PaginatedFeedListState extends ConsumerState<PaginatedFeedList> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _displayIds = [];
  bool _isRefilling = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialPosts?.isNotEmpty ?? false) {
        ref
            .read(postStoreProvider.notifier)
            .registerPosts(
              widget.initialPosts!,
              forFeedType: widget.feedType ?? 'global',
            );
      }
      _syncDisplayIds();
      // Only refill if empty or we need more for the first page
      if (_displayIds.length < widget.pageSize) {
        _checkRefill();
      }
    });
  }

  void _syncDisplayIds() {
    final store = ref.read(postStoreProvider);
    final notifier = ref.read(postStoreProvider.notifier);

    // 🔥 Get postIds for THIS specific feedType, not all posts
    final feedSpecificIds = widget.feedType != null
        ? (store.postIdsByFeedType[widget.feedType!] ?? [])
        : store.postIds;

    final newFreshIds = feedSpecificIds.where((id) {
      if (_displayIds.contains(id)) return false;
      if (id == widget.postId) return true;
      return true; // Always allow, stop hiding soft-seen
    }).toList();

    if (newFreshIds.isNotEmpty) {
      if (kDebugMode) {
        print(
          '[PaginatedFeedList] Syncing ${widget.feedType}: adding ${newFreshIds.length} new IDs',
        );
        print(
          '[PaginatedFeedList] feedSpecificIds total: ${feedSpecificIds.length}',
        );
      }
      setState(() {
        _displayIds.addAll(newFreshIds);
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
      await ref.read(postStoreProvider.notifier).loadMore(
        feedType: widget.feedType!,
        authorId: widget.authorId,
        mediaType: widget.mediaType,
        latitude: widget.feedType == 'local' ? LocationService.currentPosition?.latitude : null,
        longitude: widget.feedType == 'local' ? LocationService.currentPosition?.longitude : null,
      );
    }
  }

  Future<void> _checkRefill() async {
    if (_isRefilling || !mounted) return;

    final store = ref.read(postStoreProvider);
    final notifier = ref.read(postStoreProvider.notifier);

    final freshIds = store.postIds;

    if (freshIds.length < widget.pageSize) {
      setState(() => _isRefilling = true);
      try {
        await _triggerLoadMore();
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) await _checkRefill();
      } finally {
        if (mounted) setState(() => _isRefilling = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    if (_displayIds.isEmpty && (store.isLoading || _isRefilling)) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_displayIds.isEmpty) {
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
              controller: PageController(initialPage: widget.startIndex),
              itemCount: _displayIds.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
                if (index >= _displayIds.length - 2) _checkRefill();
              },
              itemBuilder: (context, index) {
                final postId = _displayIds[index];
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
