import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/post.dart';
import '../models/feed_type.dart';
import '../store/post_store.dart';
import '../services/feed_service.dart';
import '../services/post_lifecycle_service.dart';

/// The FeedState stores ONLY the metadata and the list of IDs.
class FeedState {
  final List<String> postIds;
  final Set<String> seenIds;
  final bool isLoading;
  final bool hasMore;
  final dynamic cursor;
  final FeedStage stage;
  final String? error;
  final int retryCount;

  FeedState({
    required this.postIds,
    required this.seenIds,
    this.isLoading = false,
    this.hasMore = true,
    this.cursor,
    required this.stage,
    this.error,
    this.retryCount = 0,
  });

  FeedState copyWith({
    List<String>? postIds,
    Set<String>? seenIds,
    bool? isLoading,
    bool? hasMore,
    dynamic cursor,
    FeedStage? stage,
    String? error,
    int? retryCount,
  }) {
    return FeedState(
      postIds: postIds ?? this.postIds,
      seenIds: seenIds ?? this.seenIds,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      cursor: cursor ?? this.cursor,
      stage: stage ?? this.stage,
      error: error ?? this.error,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// The Brain of the Feed System.
class FeedController extends StateNotifier<FeedState> {
  final FeedType type;
  final String? authorId; 
  final FeedService _service;
  final PostStore _store;
  StreamSubscription? _lifecycleSub;

  static const int _maxRetries = 2;
  static const int _weakStageThreshold = 5;

  FeedController({
    required this.type,
    this.authorId,
    required FeedService service,
    required PostStore store,
    required PostLifecycleService lifecycle,
  }) : _service = service, _store = store, 
       super(FeedState(postIds: [], seenIds: {}, stage: FeedStage.ultraLocal)) {
    
    // 🧱 Burn-in Sync: Listen for global creation/deletion events
    _lifecycleSub = lifecycle.events.listen((event) {
      if (event.type == PostEvent.created && event.post != null) {
        // Only add to Home/Global or the correct Author feed
        if (type == FeedType.home || type == FeedType.global || (type == FeedType.profile && authorId == event.post!.authorId)) {
          addPostManually(event.post!);
        }
      } else if (event.type == PostEvent.deleted && event.postId != null) {
        removePost(event.postId!);
      }
    });
  }

  @override
  void dispose() {
    _lifecycleSub?.cancel();
    super.dispose();
  }

  /// Initial Load
  Future<void> loadInitialPosts() async {
    state = state.copyWith(
      isLoading: true,
      postIds: [],
      seenIds: {},
      cursor: null,
      stage: FeedStage.ultraLocal,
      retryCount: 0,
    );

    await _fetchBatch();
  }

  /// Load More 
  Future<void> loadMore() async {
    if (state.isLoading) return;

    state = state.copyWith(retryCount: 0);

    // If current stage is exhausted, transition (only for non-profile feeds)
    if (!state.hasMore && type != FeedType.profile) {
      final next = _getNextStage(state.stage);
      if (next == null) return; 

      state = state.copyWith(
        stage: next,
        hasMore: true,
        cursor: null,
      );
      return _fetchBatch();
    }

    if (state.hasMore) {
       await _fetchBatch();
    }
  }

  /// Internal fetch logic
  Future<void> _fetchBatch() async {
    state = state.copyWith(isLoading: true);

    try {
      final batch = await _service.fetchFeedBatch(
        type: type,
        stage: state.stage,
        authorId: authorId,
        cursor: state.cursor,
      );

      // SSOT mapping and Deduplication
      final newItems = batch.posts.where((p) => !state.seenIds.contains(p.id)).toList();
      _store.upsertPosts(newItems);
      
      List<String> newPostIds = newItems.map((p) => p.id).toList();

      // Update State
      bool isStageEnding = !batch.hasMore || (newPostIds.length < _weakStageThreshold);

      state = state.copyWith(
        postIds: [...state.postIds, ...newPostIds],
        seenIds: {...state.seenIds, ...newPostIds},
        isLoading: false,
        cursor: batch.nextCursor,
        // Profile feed doesn't use the discovery pipeline, it just follows the 'hasMore' signal
        hasMore: type == FeedType.profile ? batch.hasMore : (!isStageEnding || state.stage == FeedStage.recycle),
        error: null,
      );

      // Recursion Guard for Discovery Engine (Homie only)
      if (type != FeedType.profile && newPostIds.isEmpty && state.hasMore) {
        if (state.retryCount < _maxRetries) {
          state = state.copyWith(retryCount: state.retryCount + 1);
          return _fetchBatch();
        } else {
          state = state.copyWith(hasMore: false, isLoading: false);
          return loadMore(); 
        }
      }
      
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Manually inject a post into the feed (e.g. after a new post is created).
  void addPostManually(Post post) {
    if (state.postIds.contains(post.id)) return;
    
    // SSOT Sync
    _store.upsertPost(post);
    
    // Feed Sync
    state = state.copyWith(
      postIds: [post.id, ...state.postIds],
      seenIds: {...state.seenIds, post.id},
    );
  }

  /// Remove a post from this feed by ID.
  void removePost(String postId) {
    if (!state.postIds.contains(postId)) return;
    
    // SSOT Sync
    _store.removePost(postId);
    
    // Feed Sync
    state = state.copyWith(
      postIds: state.postIds.where((id) => id != postId).toList(),
    );
  }

  FeedStage? _getNextStage(FeedStage current) {
    switch (current) {
      case FeedStage.ultraLocal: return FeedStage.city;
      case FeedStage.city: return FeedStage.regionTrending;
      case FeedStage.regionTrending: return FeedStage.global;
      case FeedStage.global: return FeedStage.mixed;
      case FeedStage.mixed: return FeedStage.recycle;
      default: return null;
    }
  }
}

// ── Feed Providers ──────────────────────────────────────────────

/// Global Feed for Home
final homeFeedControllerProvider = StateNotifierProvider<FeedController, FeedState>((ref) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return FeedController(type: FeedType.home, service: service, store: store, lifecycle: lifecycle);
});

/// Global Discovery Feed
final globalFeedControllerProvider = StateNotifierProvider<FeedController, FeedState>((ref) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return FeedController(type: FeedType.global, service: service, store: store, lifecycle: lifecycle);
});

/// ✅ NEW: Family Provider for Specific Authors (Profile Feed)
final authorFeedControllerProvider = StateNotifierProvider.family<FeedController, FeedState, String>((ref, authorId) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return FeedController(
    type: FeedType.profile, 
    authorId: authorId, 
    service: service, 
    store: store,
    lifecycle: lifecycle,
  );
});
