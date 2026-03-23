import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/core/events/feed_events.dart';

class PostInteraction {
  final String postId;
  final int likeCount;
  final int commentCount;
  final bool isLiked;

  PostInteraction({
    required this.postId,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
  });

  PostInteraction copyWith({
    int? likeCount,
    int? commentCount,
    bool? isLiked,
  }) {
    return PostInteraction(
      postId: postId,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

class PostInteractionNotifier extends StateNotifier<Map<String, PostInteraction>> {
  PostInteractionNotifier() : super({}) {
    // 🔥 Global Sync: Listen to FeedEventBus
    FeedEventBus.events.listen((event) {
      if (event.type == FeedEventType.postLiked) {
        final data = event.data as Map<String, dynamic>;
        updateLike(
          data['postId'],
          isLiked: data['isLiked'],
          likeCount: data['likeCount'],
        );
      } else if (event.type == FeedEventType.commentAdded) {
        final data = event.data as Map<String, dynamic>;
        updateCommentCount(data['postId'], data['commentCount']);
      }
    });
  }

  void initializePost(Post post) {
    if (state.containsKey(post.id)) return;
    state = {
      ...state,
      post.id: PostInteraction(
        postId: post.id,
        likeCount: post.likeCount,
        commentCount: post.commentCount,
        isLiked: post.isLiked,
      ),
    };
  }

  void updateLike(String postId, {bool? isLiked, int? likeCount}) {
    final existing = state[postId];
    if (existing == null) return;
    state = {
      ...state,
      postId: existing.copyWith(
        isLiked: isLiked,
        likeCount: likeCount,
      ),
    };
  }

  void updateCommentCount(String postId, int count) {
    final existing = state[postId];
    if (existing == null) {
      // 🚀 Auto-initialize if missing (e.g. background socket event)
      state = {
        ...state,
        postId: PostInteraction(
          postId: postId,
          likeCount: 0, // Placeholder
          commentCount: count,
          isLiked: false,
        ),
      };
      return;
    }
    state = {
      ...state,
      postId: existing.copyWith(commentCount: count),
    };
  }
}

final postInteractionProvider =
    StateNotifierProvider<PostInteractionNotifier, Map<String, PostInteraction>>(
        (ref) => PostInteractionNotifier());

final postProvider = Provider.family<PostInteraction?, String>((ref, postId) {
  final allInteractions = ref.watch(postInteractionProvider);
  return allInteractions[postId];
});

// --- Comment Cache Logic ---

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
  static const int maxCachePosts = 20;
  static const Duration cacheExpiry = Duration(minutes: 2);
  Timer? _cleanupTimer;

  CommentCacheNotifier(this._ref) : super({}) {
    _startCleanupTimer();
    
    // 🔥 Global Sync: Listen to comment events via socket or UI
    FeedEventBus.events.listen((event) {
      if (event.type == FeedEventType.commentAdded) {
        final data = event.data as Map<String, dynamic>;
        if (data['newComment'] != null) {
          final newComment = Comment.fromJson(data['newComment'] as Map<String, dynamic>);
          addComment(data['postId'], newComment);
        }
      }
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      final keysToRemove = state.entries
          .where((e) => now.difference(e.value.lastFetched) > cacheExpiry)
          .map((e) => e.key)
          .toList();
      if (keysToRemove.isNotEmpty) {
        state = Map.from(state)..removeWhere((k, v) => keysToRemove.contains(k));
      }
    });
  }

  Future<void> preload(String postId) async {
    final existing = state[postId];
    final now = DateTime.now();
    
    // Skip if already cached and fresh (< 60s)
    if (existing != null && now.difference(existing.lastFetched) < const Duration(seconds: 60)) {
      return;
    }

    try {
      final response = await BackendService.instance.getComments(postId);
      if (response.success && response.data != null) {
        final comments = (response.data as List)
            .map((c) => Comment.fromJson(c))
            .toList();
        updateCache(postId, comments, nextCursor: response.pagination?.cursor);
      }
    } catch (e) {
      // Background preload failure is silent
    }
  }

  void updateCache(String postId, List<Comment> comments, {String? nextCursor, bool isAppend = false}) {
    final now = DateTime.now();
    final currentState = state;
    
    List<Comment> updatedList;
    final existing = currentState[postId];
    if (isAppend && existing != null) {
      updatedList = [...existing.comments, ...comments];
    } else {
      updatedList = comments;
    }

    final uniqueMap = {for (var c in updatedList) c.id: c};
    updatedList = uniqueMap.values.toList();

    final newState = Map<String, CommentCache>.from(currentState);
    
    if (newState.length >= maxCachePosts && !newState.containsKey(postId)) {
      final oldestKey = newState.keys.first;
      newState.remove(oldestKey);
    }

    newState[postId] = CommentCache(
      comments: updatedList,
      lastFetched: now,
      nextCursor: nextCursor,
    );
    state = newState;
  }

  void addComment(String postId, Comment comment) {
    final currentState = state;
    final existing = currentState[postId];
    if (existing == null) return;

    if (existing.comments.any((c) => c.id == comment.id)) return;

    state = {
      ...currentState,
      postId: CommentCache(
        comments: [comment, ...existing.comments],
        lastFetched: existing.lastFetched,
        nextCursor: existing.nextCursor,
      ),
    };
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }
}

final commentCacheProvider = StateNotifierProvider<CommentCacheNotifier, Map<String, CommentCache>>((ref) => CommentCacheNotifier(ref));
