import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/post_service.dart';
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
  final Map<String, bool> isLoadingByFeedType;
  final Map<String, bool> hasMoreByFeedType; // 🔥 Track hasMore per feed type
  final Map<String, String?> errorByFeedType; // 🔥 Track error per feed type

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
    this.isLoadingByFeedType = const {},
    this.hasMoreByFeedType = const {},
    this.errorByFeedType = const {},
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
    Map<String, bool>? isLoadingByFeedType,
    Map<String, bool>? hasMoreByFeedType,
    Map<String, String?>? errorByFeedType,
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
      isLoadingByFeedType: isLoadingByFeedType ?? this.isLoadingByFeedType,
      hasMoreByFeedType: hasMoreByFeedType ?? this.hasMoreByFeedType,
      errorByFeedType: errorByFeedType ?? this.errorByFeedType,
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

  /// 🔥 Register posts with control over insertion order
  /// [prepend] = true for new posts (insert at beginning)
  /// [prepend] = false for pagination (append to end)
  void registerPosts(
    List<Post> newPosts, {
    required String forFeedType,
    bool prepend = true,  // 🔥 Default to prepend for new posts
  }) {
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
          final merged = existing.copyWith(
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
          if (merged != existing) {
            changed = true;
          }
          updatedPosts[post.id] = merged;
        }
      }

      if (changed || _isBatching) {
        // 🔥 FIX: Insert new IDs at BEGINNING so newest posts appear first (Instagram-style)
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

        // 🔥 INSERT AT BEGINNING or END based on prepend flag
        // prepend=true: new posts go first (Instagram-style)
        // prepend=false: pagination posts go last
        final List<String> finalIds = prepend
            ? [...newIds, ...currentIds]  // New posts first
            : [...currentIds, ...newIds]; // Pagination: append to end

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

        final currentFeedIds = updatedFeedIds[forFeedType] ?? [];
        final feedIdSet = currentFeedIds.toSet();

        // 🔥 FIX: Register IDs to this feed even if they are already known globally
        final newFeedIds = newPosts
            .map((p) => p.id)
            .where((id) => !feedIdSet.contains(id))
            .toList();

        // 🔥 INSERT AT BEGINNING or END for feed-specific IDs too
        updatedFeedIds[forFeedType] = prepend
            ? [...newFeedIds, ...currentFeedIds]  // New posts first
            : [...currentFeedIds, ...newFeedIds]; // Pagination: append to end

        if (kDebugMode) {
          print(
            "[PostStore] Feed '$forFeedType' now has ${updatedFeedIds[forFeedType]!.length} posts",
          );
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
    if (state.isLoadingByFeedType[feedType] == true) return;
    
    // 🔥 Clear error state when starting a new load
    final errors = Map<String, String?>.from(state.errorByFeedType);
    errors[feedType] = null;

    final loadingByFeed = Map<String, bool>.from(state.isLoadingByFeedType);
    loadingByFeed[feedType] = true;
    _updateState(state.copyWith(
      isLoading: true, 
      isLoadingByFeedType: loadingByFeed,
      errorByFeedType: errors,
    ));

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
      debugPrint('[PostStore] ❌ Load more error ($feedType): $e');
      final errors = Map<String, String?>.from(state.errorByFeedType);
      errors[feedType] = e.toString();
      _updateState(state.copyWith(errorByFeedType: errors));
    } finally {
      final updatedLoadingByFeed = Map<String, bool>.from(state.isLoadingByFeedType);
      updatedLoadingByFeed[feedType] = false;
      final hasAnyLoading = updatedLoadingByFeed.values.any((v) => v);
      _updateState(
        state.copyWith(
          isLoading: hasAnyLoading,
          isLoadingByFeedType: updatedLoadingByFeed,
        ),
      );
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

      final hasMoreMap = Map<String, bool>.from(state.hasMoreByFeedType);
      hasMoreMap['local'] = response.hasMore;
      _updateState(state.copyWith(hasMoreByFeedType: hasMoreMap));

      _localHasMore = response.hasMore;
      
      if (response.data.isNotEmpty) {
        // Register internally first
        batchUpdate(() {
          registerPosts(response.data, forFeedType: 'all_known', prepend: false);
          
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
        }).where((p) => !state.localSeenIds.contains(p.id) && (p.distance ?? 99999) <= 50.0).toList();

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
    
    final hasMoreMap = Map<String, bool>.from(state.hasMoreByFeedType);
    hasMoreMap['local'] = true;
    _updateState(state.copyWith(hasMoreByFeedType: hasMoreMap));

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

  /// 🔥 NEAREST-FIRST with Unseen Priority AND Distance Filter
  /// Sorts: Unseen posts first (by distance), then seen posts (by distance)
  /// Filters: Only posts within maxRadiusKm (default 50km for local feed)
  List<Post> _getAllPostsWithDistance(double latitude, double longitude, {double maxRadiusKm = 50.0}) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;

    final withDistance = <Post>[];
    int excludedCount = 0;
    int noCoordsCount = 0;
    
    for (final p in currentPosts.values) {
      if (p.latitude != null && p.longitude != null) {
        double d;
        if (p.distance != null) {
          d = p.distance!;
        } else {
          d = Geolocator.distanceBetween(
            latitude, longitude, p.latitude!, p.longitude!,
          ) / 1000;
        }
        
        // 🔥 FILTER: Only include posts within maxRadiusKm
        if (d <= maxRadiusKm) {
          withDistance.add(p.copyWith(distance: d));
        } else {
          excludedCount++;
          if (kDebugMode && excludedCount <= 3) {
            debugPrint('[PostStore] 🚫 Excluding post ${p.id.substring(0, 8)}... from ${p.city ?? 'unknown'} at ${d.toStringAsFixed(1)}km (max: ${maxRadiusKm}km)');
          }
        }
      } else {
        noCoordsCount++;
        // Posts without coordinates → only include if maxRadius is very large
        if (maxRadiusKm >= 99999) {
          withDistance.add(p.copyWith(distance: 99999));
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('[PostStore] 📍 Distance filter: ${withDistance.length}/${currentPosts.length} posts within ${maxRadiusKm}km (excluded: $excludedCount far, $noCoordsCount no coords)');
    }

    // 🔥 SORT: Unseen first, then by distance, then by recency
    const distanceTolerance = 0.1; // 100 meters
    withDistance.sort((a, b) {
      // 1. First: Check if seen vs unseen
      final aSeen = state.localSeenIds.contains(a.id) || state.seenIds.containsKey(a.id);
      final bSeen = state.localSeenIds.contains(b.id) || state.seenIds.containsKey(b.id);
      
      if (aSeen != bSeen) {
        return aSeen ? 1 : -1; // Unseen (-1) comes before Seen (1)
      }
      
      // 2. Both in same group (both seen or both unseen) → Sort by distance
      final da = a.distance ?? double.infinity;
      final db = b.distance ?? double.infinity;
      final diff = da - db;
      
      if (diff.abs() > distanceTolerance) {
        return diff.compareTo(0); // Nearest first
      }
      
      // 3. Same distance → Newest first
      return b.createdAt.compareTo(a.createdAt);
    });

    return withDistance;
  }

  /// Show a batch of local posts and mark as seen
  void _showLocalBatch(List<Post> batch) {
    final newSeenIds = Set<String>.from(state.localSeenIds);
    final now = DateTime.now();
    for (final p in batch) {
      newSeenIds.add(p.id);
      _localSeenTimestamps[p.id] = now;
    }

    batchUpdate(() {
      registerPosts(batch, forFeedType: 'local', prepend: false);
      _updateState((_isBatching ? _batchState! : state).copyWith(
        localSeenIds: newSeenIds,
      ));
    });

    // 🔥 DEBUG: Show sort breakdown
    final unseenCount = batch.where((p) => 
      !state.localSeenIds.contains(p.id) && !state.seenIds.containsKey(p.id)
    ).length;
    final seenCount = batch.length - unseenCount;
    final nearestDist = batch.isNotEmpty ? batch.first.distance?.toStringAsFixed(1) : '-';
    final farthestDist = batch.isNotEmpty ? batch.last.distance?.toStringAsFixed(1) : '-';
    
    debugPrint('[PostStore] ✅ Nearest-First Feed: ${batch.length} posts '
        '(unseen: $unseenCount, seen: $seenCount, nearest: ${nearestDist}km, farthest: ${farthestDist}km)');
  }

  /// 🔥 SMART SORT for hybrid/global feeds: Unseen first, then by trending/recency
  List<Post> _sortSmartForFeed(List<Post> posts, String feedType) {
    // Sort: Unseen posts first, then by trending score (or recency as fallback)
    posts.sort((a, b) {
      // 1. First: Check if seen vs unseen
      final aSeen = state.seenIds.containsKey(a.id);
      final bSeen = state.seenIds.containsKey(b.id);
      
      if (aSeen != bSeen) {
        return aSeen ? 1 : -1; // Unseen (-1) comes before Seen (1)
      }
      
      // 2. Both in same group → Sort by trending score (or recency)
      final scoreA = a.trendingScore ?? (a.likeCount * 2 + a.commentCount * 3);
      final scoreB = b.trendingScore ?? (b.likeCount * 2 + b.commentCount * 3);
      
      if (scoreB != scoreA) {
        return scoreB.compareTo(scoreA); // Higher score first
      }
      
      // 3. Same score → Newest first
      return b.createdAt.compareTo(a.createdAt);
    });
    
    return posts;
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
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
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

        final hasMoreMap = Map<String, bool>.from(state.hasMoreByFeedType);
        hasMoreMap[feedType] = response.hasMore;
        _updateState(state.copyWith(hasMoreByFeedType: hasMoreMap));
        debugPrint('[PostStore] ℹ️ Updated hasMoreByFeedType[$feedType] to ${response.hasMore}');

        if (response.data.isNotEmpty) {
          final feedSpecificIds = state.postIdsByFeedType[feedType] ?? [];
          final unseenPosts = response.data
              .where((p) => !feedSpecificIds.contains(p.id))
              .toList();

          if (unseenPosts.isEmpty && response.cursor == null) {
            debugPrint('[PostStore] ⚠️ No unseen posts and no cursor for $feedType');
            return;
          }

          if (unseenPosts.isNotEmpty) {
            // 🔥 SMART SORT: Apply unseen-first sorting for all feeds
            final sortedPosts = _sortSmartForFeed(unseenPosts, feedType);
            // 🔥 Pagination: append to end, don't prepend
            registerPosts(sortedPosts, forFeedType: feedType, prepend: false);
          }

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
        }
        return; // Success - exit retry loop
      } catch (e) {
        retryCount++;
        debugPrint('[PostStore] ❌ Load more error ($feedType, attempt $retryCount/$maxRetries): $e');
        
        if (retryCount >= maxRetries) {
          // Set error state after all retries failed
          final errors = Map<String, String?>.from(state.errorByFeedType);
          errors[feedType] = e.toString();
          _updateState(state.copyWith(errorByFeedType: errors));
        } else {
          // Wait before retry (exponential backoff)
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }
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

  /// 🔥 Atomic action versioning with race condition protection
  void setActionVersion(String postId, String actionType, int version) {
    batchUpdate(() {
      final currentVersions = _isBatching
          ? _batchState!.actionVersions
          : state.actionVersions;
      final versions = Map<String, Map<String, int>>.from(currentVersions);
      final postVersions = Map<String, int>.from(versions[postId] ?? {});
      
      // 🔥 FIX: Only update if new version is higher (prevents race condition overwrites)
      final currentVersion = postVersions[actionType] ?? 0;
      if (version > currentVersion) {
        postVersions[actionType] = version;
        versions[postId] = postVersions;
        _updateState(
          (_isBatching ? _batchState! : state).copyWith(actionVersions: versions),
        );
      }
    });
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

  /// Visibility-aware LRU: Keep 50 most recent visible + 100 total cached.
  static const int _maxCachedPosts = 150;

  void _checkMemoryLimits() {
    final currentState = _isBatching ? _batchState! : state;
    if (currentState.posts.length <= _maxCachedPosts) return;

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
    final targetToRemove = currentState.posts.length - _maxCachedPosts;

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

    debugPrint('[PostStore] 🧹 Memory cleanup: removed $removedCount posts, ${updatedPosts.length} remaining');
  }

  /// 🔥 Public method to trigger memory cleanup from outside
  void pruneOldPosts() {
    _checkMemoryLimits();
  }

  /// 🔥 Clear session buffer periodically to prevent unbounded growth
  void clearSessionBuffer() {
    _sessionSeenBuffer.clear();
    debugPrint('[PostStore] 🧹 Session buffer cleared');
  }

  void resetFeedState(String feedType) {
    final hasMoreMap = Map<String, bool>.from(state.hasMoreByFeedType);
    final errorMap = Map<String, String?>.from(state.errorByFeedType);
    final loadingMap = Map<String, bool>.from(state.isLoadingByFeedType);
    final cursorsMap = Map<String, Map<String, dynamic>>.from(state.lastCursors);
    final feedIdsMap = Map<String, List<String>>.from(state.postIdsByFeedType);

    hasMoreMap[feedType] = true;
    errorMap[feedType] = null;
    loadingMap[feedType] = false;
    cursorsMap[feedType] = {};
    feedIdsMap[feedType] = [];

    _updateState(state.copyWith(
      hasMoreByFeedType: hasMoreMap,
      errorByFeedType: errorMap,
      isLoadingByFeedType: loadingMap,
      lastCursors: cursorsMap,
      postIdsByFeedType: feedIdsMap,
    ));
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
    ], forFeedType: 'detail', prepend: false);
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
    List<Comment> updated;
    if (isAppend && existing != null) {
      final mergedById = <String, Comment>{};
      for (final c in existing.comments) {
        mergedById[c.id] = c;
      }
      for (final c in comments) {
        mergedById[c.id] = c;
      }
      updated = mergedById.values.toList();
    } else {
      updated = comments;
    }
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
    
    // 🔥 Dedup Protection
    if (existing.comments.any((c) => c.id == comment.id)) {
      debugPrint('[CommentCache] 🛑 Skipping duplicate comment ${comment.id}');
      return;
    }

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
