import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../core/state/post_state.dart';
import '../post/post_card.dart';

enum FeedLayoutType { list, paged }

class PaginatedFeedList extends ConsumerStatefulWidget {
  final String? feedType;
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
  final Widget Function(BuildContext context, Post post, int index, bool isCurrent)? itemBuilder;

  const PaginatedFeedList({
    super.key,
    this.feedType,
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
      _syncDisplayIds();
      _checkRefill();
    });
  }

  void _syncDisplayIds() {
    final store = ref.read(postStoreProvider);
    final notifier = ref.read(postStoreProvider.notifier);
    
    final newFreshIds = store.postIds.where((id) {
      if (_displayIds.contains(id)) return false;
      if (id == widget.postId) return true;
      return !notifier.isSoftSeen(id);
    }).toList();
    
    if (newFreshIds.isNotEmpty) {
      setState(() {
        _displayIds.addAll(newFreshIds);
      });
    }
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 600) {
      _triggerLoadMore();
    }
  }

  Future<void> _triggerLoadMore() async {
    if (widget.onLoadMore != null) {
      await widget.onLoadMore!();
    } else if (widget.feedType != null) {
      await ref.read(postStoreProvider.notifier).loadMore(
        feedType: widget.feedType!,
        mediaType: widget.mediaType,
      );
    }
  }

  Future<void> _checkRefill() async {
    if (_isRefilling || !mounted) return;
    
    final store = ref.read(postStoreProvider);
    final notifier = ref.read(postStoreProvider.notifier);
    
    final freshIds = store.postIds.where((id) => !notifier.isSoftSeen(id)).toList();
    
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
    ref.listen(postStoreProvider.select((s) => s.postIds), (prev, next) {
      _syncDisplayIds();
    });

    if (_displayIds.isEmpty && _isRefilling) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_displayIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No new posts matching your filters'),
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
      onRefresh: () async => widget.onRefresh?.call(),
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
                  return widget.itemBuilder!(context, post, index, index == _currentPage);
                }
                return PostCard(postId: postId);
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
                return PostCard(postId: postId);
              },
            ),
    );
  }
}
