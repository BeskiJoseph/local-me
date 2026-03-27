import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/models/api_response.dart';
import 'package:geolocator/geolocator.dart';


/// Central state for the entire app's post data.
class PostStoreState {
  final Map<String, Post> posts;

  /// actionVersions[postId][actionType] -> latest timestamp/version
  final Map<String, Map<String, int>> actionVersions;

  /// Tracks which posts are currently on-screen to prevent memory pruning.
  final Set<String> visibleIds;
  final List<String> postIds;
  final Map<String, DateTime> seenIds;

  /// 🔥 Track postIds per feed type to avoid cross-feed mixing
  final Map<String, List<String>> postIdsByFeedType;

  /// 🔥 Multi-radius local feed state
  final int localRadiusIndex;       // current index into radiusSteps
  final Set<String> localSeenIds;   // dedup across radius expansions
  final bool isLoading;             // tracks initial/global loading state

  PostStoreState({
    this.posts = const {},
    this.actionVersions = const {},
    this.visibleIds = const {},
    this.postIds = const [],
    this.seenIds = const {},
    this.lastCursors = const {},
    this.postIdsByFeedType = const {},
    this.localRadiusIndex = 0,
    this.localSeenIds = const {},
    this.isLoading = false,
  });

  PostStoreState copyWith({
    Map<String, Post>? posts,
    Map<String, Map<String, int>>? actionVersions,
    Set<String>? visibleIds,
    List<String>? postIds,
    Map<String, DateTime>? seenIds,
    Map<String, Map<String, dynamic>>? lastCursors,
    Map<String, List<String>>? postIdsByFeedType,
    int? localRadiusIndex,
    Set<String>? localSeenIds,
    bool? isLoading,
  }) {
    return PostStoreState(
      posts: posts ?? this.posts,
      actionVersions: actionVersions ?? this.actionVersions,
      visibleIds: visibleIds ?? this.visibleIds,
      postIds: postIds ?? this.postIds,
      seenIds: seenIds ?? this.seenIds,
      lastCursors: lastCursors ?? this.lastCursors,
      postIdsByFeedType: postIdsByFeedType ?? this.postIdsByFeedType,
      localRadiusIndex: localRadiusIndex ?? this.localRadiusIndex,
      localSeenIds: localSeenIds ?? this.localSeenIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// tracks the last cursors returned by the backend for each feed type
  final Map<String, Map<String, dynamic>> lastCursors;
}


class PostStoreNotifier extends StateNotifier<PostStoreState> {
  PostStoreNotifier() : super(PostStoreState());

  bool _isBatching = false;
  PostStoreState? _batchState;

  /// 🔥 Multi-radius constants
  static const List<double> radiusSteps = [1, 5, 10, 25, 50];
  static const int _maxRetries = 3;
  int _localRetryCount = 0;
  bool _localHasMore = true;
  bool _isRecycleMode = false;
  final Map<String, DateTime> _localSeenTimestamps = {};

  /// Session-level buffer to prevent redundant state updates within the same session.
  final Set<String> _sessionSeenBuffer = {};

  // --- Batching Support ---

  void batchUpdate(void Function() fn) {
    if (_isBatching) {
      fn();
      return;
    }
    _isBatching = true;
    _batchState = state;
    try {
      fn();
      state = _batchState!;
    } finally {
      _isBatching = false;
      _batchState = null;
    }
  }

  void _updateState(PostStoreState newState) {
    if (_isBatching) {
      _batchState = newState;
    } else {
      state = newState;
    }
  }

  // --- Registration & Updates ---

  void registerPosts(List<Post> newPosts, {required String forFeedType}) {
    // 🔥 CRITICAL: feedType MUST be provided - never allow "unknown"
    if (forFeedType.isEmpty || forFeedType == 'unknown') {
      throw Exception(
        'registerPosts: forFeedType is REQUIRED and must not be "unknown". '
        'Got: "$forFeedType". Pass explicit feed type: local/global/reels/detail',
      );
    }

    // 🔥 CRITICAL PROTECTION: Never wipe state if new data is empty
    if (newPosts.isEmpty) {
      return;
    }

    batchUpdate(() {
      final currentPosts = _isBatching ? _batchState!.posts : state.posts;
      final updatedPosts = Map<String, Post>.from(currentPosts);
      bool changed = false;

      for (final post in newPosts) {
        if (!updatedPosts.containsKey(post.id)) {
          updatedPosts[post.id] = post;
          changed = true;
        } else {
          // Merge logic: only update if something meaningful changed
          final existing = updatedPosts[post.id]!;
          updatedPosts[post.id] = existing.copyWith(
            mediaUrl: post.mediaUrl,
            thumbnailUrl: post.thumbnailUrl,
            body: post.body,
            isLiked: post.isLiked,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            isBookmarked: post.isBookmarked,
            computedStatus: post.computedStatus,
            scope: post.scope,
          );
        }
      }

      if (changed || _isBatching) {
        // 🔥 FIX: Maintain stable order while appending new IDs
        final List<String> currentIds = _isBatching
            ? _batchState!.postIds
            : state.postIds;
        final Set<String> idSet = currentIds.toSet();
        final List<String> newIds = [];

        for (final post in newPosts) {
          if (!idSet.contains(post.id)) {
            newIds.add(post.id);
            idSet.add(post.id);
          }
        }

        final List<String> finalIds = [...currentIds, ...newIds];

        if (kDebugMode) {
          print("[PostStore] UI FINAL IDS: $finalIds");
          print(
            "[PostStore] ✅ Feed type: $forFeedType, new IDs added: ${newIds.length}",
          );
        }

        // 🔥 Also track per-feed postIds
        final updatedFeedIds = Map<String, List<String>>.from(
          _isBatching
              ? _batchState!.postIdsByFeedType
              : state.postIdsByFeedType,
        );

        if (forFeedType != null) {
          final currentFeedIds = updatedFeedIds[forFeedType] ?? [];
          final feedIdSet = currentFeedIds.toSet();
          
          // 🔥 FIX: Register IDs to this feed even if they are already known globally
          final newFeedIds = newPosts
              .map((p) => p.id)
              .where((id) => !feedIdSet.contains(id))
              .toList();
              
          updatedFeedIds[forFeedType] = [...currentFeedIds, ...newFeedIds];

          if (kDebugMode) {
            print(
              "[PostStore] Feed '$forFeedType' now has ${updatedFeedIds[forFeedType]!.length} posts",
            );
          }
        }


        _updateState(
          (_isBatching ? _batchState! : state).copyWith(
            posts: updatedPosts,
            postIds: finalIds,
            postIdsByFeedType: updatedFeedIds,
          ),
        );
      }
    });
  }

  /// Centralized pagination trigger.
  Future<void> loadMore({
    required String feedType,
    String? mediaType,
    String? authorId,
    double? latitude,
    double? longitude,
  }) async {
    if (state.isLoading) return;
    _updateState(state.copyWith(isLoading: true));

    try {
      if (feedType == 'local') {
        await _loadMoreLocal(
          mediaType: mediaType,
          latitude: latitude,
          longitude: longitude,
        );
      } else {
        await _loadMoreStandard(
          feedType: feedType,
          mediaType: mediaType,
          authorId: authorId,
          latitude: latitude,
          longitude: longitude,
        );
      }
    } catch (e) {
      debugPrint('[PostStore] ❌ Load more error: $e');
    } finally {
      _updateState(state.copyWith(isLoading: false));
    }
  }

  // ─────────────────────────────────────────────────────────
  // 🔥 INSTAGRAM-STYLE LOCAL FEED
  // Phase 1: Distance-sorted → show closest first (batches of 15)
  // Phase 2: Show ALL remaining posts (no distance filter)
  // Phase 3: Recycle → reset and loop
  // ─────────────────────────────────────────────────────────
  Future<void> _loadMoreLocal({
    String? mediaType,
    double? latitude,
    double? longitude,
  }) async {
    if (latitude == null || longitude == null) return;

    // 1. Get current unseen pool
    final allPosts = _getAllPostsWithDistance(latitude, longitude);
    final unseenPool = allPosts.where((p) => !state.localSeenIds.contains(p.id)).toList();

    debugPrint('[PostStore] 📊 Pool Status: Store=${allPosts.length}, Unseen=${unseenPool.length}, Seen=${state.localSeenIds.length}');

    // 2. Refill pool if low
    if (_localHasMore && unseenPool.length < 15) {
      debugPrint('[PostStore] 📡 Pool low → Fetching from backend');
      
      final currentCursors = (state.lastCursors['local']?.isEmpty ?? true)
          ? null
          : state.lastCursors['local'];

      final response = await PostService.getPostsPaginated(
        feedType: 'local',
        limit: 15,
        lastCursors: currentCursors,
        mediaType: mediaType,
        latitude: latitude,
        longitude: longitude,
      );

      _localHasMore = response.hasMore;
      
      if (response.data.isNotEmpty) {
        // Register internally first
        batchUpdate(() {
          registerPosts(response.data, forFeedType: 'all_known');
          
          if (response.cursor != null) {
            final updatedCursors = Map<String, Map<String, dynamic>>.from(state.lastCursors);
            updatedCursors['local'] = response.cursor!;
            _updateState(state.copyWith(lastCursors: updatedCursors));
          }
        });

        // Compute distances and find truly new posts
        final newlyFetched = response.data.map((p) {
          if (p.latitude != null && p.longitude != null) {
             final d = Geolocator.distanceBetween(latitude, longitude, p.latitude!, p.longitude!);
             return p.copyWith(distance: d / 1000);
          }
          return p.copyWith(distance: 99999);
        }).where((p) => !state.localSeenIds.contains(p.id)).toList();

        if (newlyFetched.isNotEmpty) {
           debugPrint('[PostStore] ✅ Showing ${newlyFetched.length} newly fetched posts');
           _showLocalBatch(newlyFetched);
           return;
        }
      }
    }

    // 3. Show from existing pool if we have any
    if (unseenPool.isNotEmpty) {
      final batch = unseenPool.take(15).toList();
      debugPrint('[PostStore] 📦 Showing ${batch.length} posts from existing pool');
      _showLocalBatch(batch);
      return;
    }

    // 4. Exhausted → Recycle ONLY if backend is also dead
    if (!_localHasMore) {
      debugPrint('[PostStore] ♻️ ALL content seen → Recycling');
      _recycleLocalFeed(latitude, longitude);
    } else {
      debugPrint('[PostStore] ⏳ Backend busy or no new posts yet');
    }
  }

  Future<void> _recycleLocalFeed(double latitude, double longitude) async {
    final now = DateTime.now();
    _updateState(state.copyWith(
      localSeenIds: const {},
      localRadiusIndex: 0,
    ));
    _localHasMore = true;
    _localRetryCount = 0;

    // Clear the local feed IDs to start fresh
    final updatedFeedIds = Map<String, List<String>>.from(state.postIdsByFeedType);
    updatedFeedIds['local'] = [];
    _updateState(state.copyWith(postIdsByFeedType: updatedFeedIds));

    // Get all posts, skip those seen within last 30 minutes
    final cooldownDuration = const Duration(minutes: 30);
    final allRecycled = _getAllPostsWithDistance(latitude, longitude);
    final cooledDown = allRecycled.where((p) {
      final lastSeen = _localSeenTimestamps[p.id];
      if (lastSeen == null) return true;
      return now.difference(lastSeen) > cooldownDuration;
    }).toList();

    // Shuffle for variety on recycle (not same order every time)
    cooledDown.shuffle();

    debugPrint('[PostStore] ♻️ Recycled: ${cooledDown.length}/${allRecycled.length} posts (${allRecycled.length - cooledDown.length} on cooldown)');

    if (cooledDown.isNotEmpty) {
      _showLocalBatch(cooledDown.take(15).toList());
    } else {
      debugPrint('[PostStore] ⏳ All posts on cooldown — feed paused');
    }
  }

  /// Get ALL posts from store with distance computed, sorted by distance ASC
  List<Post> _getAllPostsWithDistance(double latitude, double longitude) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;

    final withDistance = <Post>[];
    for (final p in currentPosts.values) {
      if (p.latitude != null && p.longitude != null) {
        if (p.distance != null) {
          withDistance.add(p);
        } else {
          final d = Geolocator.distanceBetween(
            latitude, longitude, p.latitude!, p.longitude!,
          ) / 1000;
          withDistance.add(p.copyWith(distance: d));
        }
      } else {
        // Posts without coordinates → add at end with max distance
        withDistance.add(p.copyWith(distance: 99999));
      }
    }

    // Sort: closest first (with 100m tolerance), then by createdAt for ties
    const distanceTolerance = 0.1; // 100 meters
    withDistance.sort((a, b) {
      final da = a.distance ?? double.infinity;
      final db = b.distance ?? double.infinity;
      
      final diff = da - db;
      if (diff.abs() > distanceTolerance) {
        return diff.compareTo(0);
      }
      
      return b.createdAt.compareTo(a.createdAt);
    });

    return withDistance;
  }

  /// Show a batch of local posts and mark as seen
  void _showLocalBatch(List<Post> batch) {
    final newSeenIds = Set<String>.from(state.localSeenIds);
    for (final p in batch) {
      newSeenIds.add(p.id);
    }

    batchUpdate(() {
      registerPosts(batch, forFeedType: 'local');
      _updateState((_isBatching ? _batchState! : state).copyWith(
        localSeenIds: newSeenIds,
      ));
    });

    debugPrint('[PostStore] ✅ Showed ${batch.length} posts (dist: ${batch.first.distance?.toStringAsFixed(1)}km → ${batch.last.distance?.toStringAsFixed(1)}km, seen: ${newSeenIds.length})');
  }

  /// Expand to next radius ring (kept for compatibility)
  void _expandRadius() {
    final nextIdx = state.localRadiusIndex + 1;
    _updateState(state.copyWith(localRadiusIndex: nextIdx));
  }


  // ─────────────────────────────────────────────────────────
  // ☁️ STANDARD BACKEND PAGINATION (global, filtered, etc.)
  // ─────────────────────────────────────────────────────────
  Future<void> _loadMoreStandard({
    required String feedType,
    String? mediaType,
    String? authorId,
    double? latitude,
    double? longitude,
  }) async {
    final currentCursors = (state.lastCursors[feedType]?.isEmpty ?? true)
        ? null
        : state.lastCursors[feedType];

    final response = (authorId != null)
        ? await PostService.getFilteredPostsPaginated(
            authorId: authorId,
            limit: 15,
            lastCursors: currentCursors,
          )
        : await PostService.getPostsPaginated(
            feedType: feedType,
            limit: 15,
            lastCursors: currentCursors,
            mediaType: mediaType,
            latitude: latitude,
            longitude: longitude,
          );

    if (response.data.isNotEmpty) {
      // Loop detection
      final firstNewPostId = response.data.first.id;
      final feedSpecificIds = state.postIdsByFeedType[feedType] ?? [];
      if (feedSpecificIds.contains(firstNewPostId)) {
        debugPrint('[PostStore] ⚠️ PAGINATION LOOP DETECTED for $feedType');
        return;
      }

      batchUpdate(() {
        registerPosts(response.data, forFeedType: feedType);

        // Update cursor
        if (response.cursor != null) {
          final updatedCursors = Map<String, Map<String, dynamic>>.from(
            (_isBatching ? _batchState! : state).lastCursors,
          );
          updatedCursors[feedType] = response.cursor!;
          _updateState((_isBatching ? _batchState! : state).copyWith(
            lastCursors: updatedCursors,
          ));
        }
      });
    }
  }

  bool _hasPendingAction(String postId, String actionType) {
    final versions = _isBatching
        ? _batchState!.actionVersions
        : state.actionVersions;
    return (versions[postId]?[actionType] ?? 0) > 0;
  }

  void updatePostPartially(String postId, Map<String, dynamic> updates) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;
    final current = currentPosts[postId];
    if (current == null) return;

    final updated = current.copyWith(
      title: updates['title'],
      body: updates['body'] ?? updates['text'],
      likeCount: updates['likeCount'],
      commentCount: updates['commentCount'],
      isLiked: updates['isLiked'],
      isFollowing: updates['isFollowing'],
      isBookmarked: updates['isBookmarked'],
      attendeeCount: updates['attendeeCount'],
    );

    final updatedPosts = Map<String, Post>.from(currentPosts);
    updatedPosts[postId] = updated;

    _updateState(
      (_isBatching ? _batchState! : state).copyWith(posts: updatedPosts),
    );
  }

  void updatePostPartiallyByAuthor(
    String authorId,
    Map<String, dynamic> updates,
  ) {
    batchUpdate(() {
      final currentPosts = _isBatching ? _batchState!.posts : state.posts;
      final updatedPosts = Map<String, Post>.from(currentPosts);
      bool changed = false;

      for (final entry in currentPosts.entries) {
        if (entry.value.authorId == authorId) {
          updatedPosts[entry.key] = entry.value.copyWith(
            isFollowing: updates['isFollowing'] ?? entry.value.isFollowing,
          );
          changed = true;
        }
      }

      if (changed) {
        _updateState(
          (_isBatching ? _batchState! : state).copyWith(posts: updatedPosts),
        );
      }
    });
  }

  void incrementCommentCount(String postId) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;
    final post = currentPosts[postId];
    if (post == null) return;
    updatePostPartially(postId, {'commentCount': post.commentCount + 1});
  }

  void removePost(String postId) {
    batchUpdate(() {
      final currentPosts = _isBatching ? _batchState!.posts : state.posts;
      if (!currentPosts.containsKey(postId)) return;

      final updatedPosts = Map<String, Post>.from(currentPosts);
      updatedPosts.remove(postId);

      final currentIds = _isBatching ? _batchState!.postIds : state.postIds;
      final updatedIds = List<String>.from(currentIds)..remove(postId);

      final currentFeedIds = _isBatching ? _batchState!.postIdsByFeedType : state.postIdsByFeedType;
      final updatedFeedIds = Map<String, List<String>>.from(currentFeedIds);
      updatedFeedIds.forEach((key, list) {
        if (list.contains(postId)) {
          updatedFeedIds[key] = List<String>.from(list)..remove(postId);
        }
      });

      _updateState((_isBatching ? _batchState! : state).copyWith(
        posts: updatedPosts,
        postIds: updatedIds,
        postIdsByFeedType: updatedFeedIds,
      ));
    });
  }

  // --- Action Versioning (Race Condition Protection) ---

  void setActionVersion(String postId, String actionType, int version) {
    final currentVersions = _isBatching
        ? _batchState!.actionVersions
        : state.actionVersions;
    final versions = Map<String, Map<String, int>>.from(currentVersions);
    final postVersions = Map<String, int>.from(versions[postId] ?? {});
    postVersions[actionType] = version;
    versions[postId] = postVersions;
    _updateState(
      (_isBatching ? _batchState! : state).copyWith(actionVersions: versions),
    );
  }

  // --- Seen Tracking (Soft Seen System) ---

  void markAsSeen(String postId) {
    // PROTECT: Skip if already marked in this session to prevent redundant state noise.
    if (_sessionSeenBuffer.contains(postId)) return;
    _sessionSeenBuffer.add(postId);

    batchUpdate(() {
      final currentSeen = _isBatching ? _batchState!.seenIds : state.seenIds;

      // OPTIMIZATION: Only update if not already seen in the last 60 mins (Soft Seen)
      final existingAt = currentSeen[postId];
      if (existingAt != null &&
          DateTime.now().difference(existingAt).inMinutes < 60) {
        return;
      }

      final updatedSeen = Map<String, DateTime>.from(currentSeen);
      updatedSeen[postId] = DateTime.now();

      _updateState(
        (_isBatching ? _batchState! : state).copyWith(seenIds: updatedSeen),
      );

      if (updatedSeen.length % 50 == 0) {
        _cleanupOldSeen();
      }
    });
  }

  void _cleanupOldSeen() {
    final now = DateTime.now();
    final currentSeen = _isBatching ? _batchState!.seenIds : state.seenIds;
    final updatedSeen = Map<String, DateTime>.from(currentSeen);

    updatedSeen.removeWhere(
      (id, timestamp) => now.difference(timestamp).inHours > 24,
    );

    _updateState(
      (_isBatching ? _batchState! : state).copyWith(seenIds: updatedSeen),
    );
  }

  void clearSeen() {
    _updateState(
      (_isBatching ? _batchState! : state).copyWith(seenIds: const {}),
    );
  }

  /// Returns whether a post should be hidden based on "Soft Seen" logic (e.g. 60 min window)
  bool isSoftSeen(String postId) {
    final seenAt = state.seenIds[postId];
    if (seenAt == null) return false;

    // Hidden for 60 minutes
    return DateTime.now().difference(seenAt).inMinutes < 60;
  }

  // --- Memory Management ---

  void setVisible(String postId, bool visible) {
    final currentVisible = _isBatching
        ? _batchState!.visibleIds
        : state.visibleIds;
    final updatedVisible = Set<String>.from(currentVisible);
    if (visible) {
      updatedVisible.add(postId);
    } else {
      updatedVisible.remove(postId);
    }
    _updateState(
      (_isBatching ? _batchState! : state).copyWith(visibleIds: updatedVisible),
    );
  }

  /// Visibility-aware LRU: Keep 100 most recent visible + 400 total cached.
  void _checkMemoryLimits() {
    final currentState = _isBatching ? _batchState! : state;
    if (currentState.posts.length <= 500) return;

    // Sort by creation time (proxy for LRU in this app)
    final sortedIds = currentState.posts.keys.toList()
      ..sort(
        (a, b) => currentState.posts[a]!.createdAt.compareTo(
          currentState.posts[b]!.createdAt,
        ),
      );

    final updatedPosts = Map<String, Post>.from(currentState.posts);
    final updatedVersions = Map<String, Map<String, int>>.from(
      currentState.actionVersions,
    );

    int removedCount = 0;
    final targetToRemove = currentState.posts.length - 500;

    for (final id in sortedIds) {
      if (removedCount >= targetToRemove) break;

      // 🔥 Hard Fix: Never purge a post if it is currently visible on screen
      if (!currentState.visibleIds.contains(id)) {
        updatedPosts.remove(id);
        updatedVersions.remove(id);
        removedCount++;
      }
    }

    // 🔥 Sync postIds with the pruned posts map
    final List<String> finalIds = currentState.postIds
        .where((id) => updatedPosts.containsKey(id))
        .toList();

    _updateState(
      currentState.copyWith(
        posts: updatedPosts,
        actionVersions: updatedVersions,
        postIds: finalIds,
      ),
    );
  }
}

// --- Providers ---

final postStoreProvider =
    StateNotifierProvider<PostStoreNotifier, PostStoreState>(
      (ref) => PostStoreNotifier(),
    );

final postProvider = Provider.family<Post?, String>((ref, postId) {
  return ref.watch(postStoreProvider.select((s) => s.posts[postId]));
});

final postActionVersionProvider = Provider.family<int, (String, String)>((
  ref,
  arg,
) {
  final postId = arg.$1;
  final actionType = arg.$2;
  return ref.watch(
    postStoreProvider.select((s) => s.actionVersions[postId]?[actionType] ?? 0),
  );
});

// --- Legacy Interop (Mapped to PostStore) ---

final postInteractionProvider =
    StateNotifierProvider<PostInteractionNotifier, Map<String, Post>>((ref) {
      return PostInteractionNotifier(ref);
    });

class PostInteractionNotifier extends StateNotifier<Map<String, Post>> {
  final Ref ref;
  PostInteractionNotifier(this.ref) : super({});

  void initializePost(Post post) {
    // Single post from detail view - track as 'detail' feed type
    ref.read(postStoreProvider.notifier).registerPosts([
      post,
    ], forFeedType: 'detail');
  }

  void updatePost(String postId, Map<String, dynamic> updates) {
    ref.read(postStoreProvider.notifier).updatePostPartially(postId, updates);
  }
}

// --- Comment Cache Logic (Kept for completeness, same patterns apply) ---

class CommentCache {
  final List<Comment> comments;
  final DateTime lastFetched;
  final String? nextCursor;
  CommentCache({
    required this.comments,
    required this.lastFetched,
    this.nextCursor,
  });
}

class CommentCacheNotifier extends StateNotifier<Map<String, CommentCache>> {
  final Ref _ref;
  CommentCacheNotifier(this._ref) : super({});

  Future<void> preload(String postId) async {
    try {
      final response = await BackendService.getComments(postId);
      if (response.success && response.data != null) {
        final comments = (response.data as List)
            .map((c) => Comment.fromJson(c))
            .toList();
        updateCache(postId, comments, nextCursor: response.pagination?.cursor);
      }
    } catch (_) {}
  }

  void updateCache(
    String postId,
    List<Comment> comments, {
    String? nextCursor,
    bool isAppend = false,
  }) {
    final existing = state[postId];
    List<Comment> updated = (isAppend && existing != null)
        ? [...existing.comments, ...comments]
        : comments;
    state = {
      ...state,
      postId: CommentCache(
        comments: updated,
        lastFetched: DateTime.now(),
        nextCursor: nextCursor,
      ),
    };
  }

  void addComment(String postId, Comment comment) {
    final existing = state[postId];
    if (existing == null) return;
    state = {
      ...state,
      postId: CommentCache(
        comments: [comment, ...existing.comments],
        lastFetched: existing.lastFetched,
        nextCursor: existing.nextCursor,
      ),
    };
    _ref.read(postStoreProvider.notifier).incrementCommentCount(postId);
  }
}

final commentCacheProvider =
    StateNotifierProvider<CommentCacheNotifier, Map<String, CommentCache>>(
      (ref) => CommentCacheNotifier(ref),
    );
