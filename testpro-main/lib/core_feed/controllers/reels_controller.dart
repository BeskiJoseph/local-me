import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/post.dart';
import '../models/feed_type.dart';
import '../store/post_store.dart';
import '../services/feed_service.dart';
import '../services/post_lifecycle_service.dart';
import 'feed_controller.dart'; // Re-use FeedState

/// Dedicated controller for the Reels vertical feed.
/// 🥉 Phase 7.3: Separation of Reels from main Feed Controller.
class ReelsController extends StateNotifier<FeedState> {
  final FeedType type;
  final String? authorId;
  final FeedService _service;
  final PostStore _store;
  StreamSubscription? _lifecycleSub;

  ReelsController({
    required this.type,
    this.authorId,
    required FeedService service,
    required PostStore store,
    required PostLifecycleService lifecycle,
  }) : _service = service, _store = store, 
       super(FeedState(postIds: [], seenIds: {}, stage: FeedStage.global)) {
    
    // 🧱 Burn-in Sync: Listen for global creation/deletion events
    _lifecycleSub = lifecycle.events.listen((event) {
      if (event.type == PostEvent.created && event.post != null) {
        if (type == FeedType.home || type == FeedType.global || (type == FeedType.profile && authorId == event.post!.authorId)) {
          // Verify it's a video for Reels
          if (event.post!.mediaType == 'video') {
            addPostManually(event.post!);
          }
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

  /// Manually inject a post into the reels feed.
  void addPostManually(Post post) {
    if (state.postIds.contains(post.id)) return;
    _store.upsertPost(post);
    state = state.copyWith(postIds: [post.id, ...state.postIds], seenIds: {...state.seenIds, post.id});
  }

  /// Remove a post from the reels by ID.
  void removePost(String postId) {
    if (!state.postIds.contains(postId)) return;
    _store.removePost(postId);
    state = state.copyWith(postIds: state.postIds.where((id) => id != postId).toList());
  }

  /// Initial Load for Reels
  Future<void> loadInitialReels() async {
    state = state.copyWith(
      isLoading: true,
      postIds: [],
      seenIds: {},
      cursor: null,
      retryCount: 0,
    );
    await _fetchReelsBatch();
  }

  /// Pagination for Reels
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchReelsBatch();
  }

  /// Internal Reel fetcher
  Future<void> _fetchReelsBatch() async {
    state = state.copyWith(isLoading: true);

    try {
      final batch = await _service.fetchFeedBatch(
        type: type,
        stage: FeedStage.global, // Reels usually focus on the Global/Mixed pool
        authorId: authorId,
        mediaType: 'video', // ✅ CRITICAL: Force video only
        cursor: state.cursor,
      );

      // SSOT mapping and Deduplication
      final newItems = batch.posts.where((p) => !state.seenIds.contains(p.id)).toList();
      _store.upsertPosts(newItems);
      
      final newPostIds = newItems.map((p) => p.id).toList();

      state = state.copyWith(
        postIds: [...state.postIds, ...newPostIds],
        seenIds: {...state.seenIds, ...newPostIds},
        isLoading: false,
        cursor: batch.nextCursor,
        hasMore: batch.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// ── Reels Providers ──────────────────────────────────────────────

/// Global Reels Provider
final globalReelsControllerProvider = StateNotifierProvider<ReelsController, FeedState>((ref) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return ReelsController(type: FeedType.global, service: service, store: store, lifecycle: lifecycle);
});

/// Local/Nearby Reels Provider
final nearbyReelsControllerProvider = StateNotifierProvider<ReelsController, FeedState>((ref) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return ReelsController(type: FeedType.home, service: service, store: store, lifecycle: lifecycle);
});

/// Author-specific Reels Provider
final authorReelsControllerProvider = StateNotifierProvider.family<ReelsController, FeedState, String>((ref, authorId) {
  final store = ref.read(postStoreProvider.notifier);
  final service = FeedService(); 
  final lifecycle = ref.read(postLifecycleProvider);
  return ReelsController(type: FeedType.profile, authorId: authorId, service: service, store: store, lifecycle: lifecycle);
});
