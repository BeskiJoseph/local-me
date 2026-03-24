import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/core/events/feed_events.dart';

/// Central state for the entire app's post data.
class PostStoreState {
  final Map<String, Post> posts;
  
  /// actionVersions[postId][actionType] -> latest timestamp/version
  final Map<String, Map<String, int>> actionVersions;
  
  /// Tracks which posts are currently on-screen to prevent memory pruning.
  final Set<String> visibleIds;
  final List<String> postIds;

  PostStoreState({
    this.posts = const {},
    this.actionVersions = const {},
    this.visibleIds = const {},
    this.postIds = const [],
  });

  PostStoreState copyWith({
    Map<String, Post>? posts,
    Map<String, Map<String, int>>? actionVersions,
    Set<String>? visibleIds,
    List<String>? postIds,
  }) {
    return PostStoreState(
      posts: posts ?? this.posts,
      actionVersions: actionVersions ?? this.actionVersions,
      visibleIds: visibleIds ?? this.visibleIds,
      postIds: postIds ?? this.postIds,
    );
  }
}

class PostStoreNotifier extends StateNotifier<PostStoreState> {
  PostStoreNotifier() : super(PostStoreState()) {
    _listenToEvents();
  }

  bool _isBatching = false;
  PostStoreState? _batchState;

  void _listenToEvents() {
    FeedEventBus.events.listen((event) {
      switch (event.type) {
        case FeedEventType.postLiked:
          final data = event.data as Map<String, dynamic>;
          updatePostPartially(data['postId'], {
            'isLiked': data['isLiked'],
            'likeCount': data['likeCount'],
          });
          break;
        case FeedEventType.userFollowed:
          final data = event.data as Map<String, dynamic>;
          updatePostPartiallyByAuthor(data['userId'], {'isFollowing': data['isFollowing']});
          break;
        case FeedEventType.commentAdded:
          final data = event.data as Map<String, dynamic>;
          incrementCommentCount(data['postId']);
          break;
        case FeedEventType.postDeleted:
          final postId = event.data is String ? event.data as String : event.data.toString();
          removePost(postId);
          break;
        case FeedEventType.postUpdated:
          final data = event.data as Map<String, dynamic>;
          updatePostPartially(data['postId'], data['updates']);
          break;
        default:
          break;
      }
    });
  }

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

  /// Registers new posts from API/Feed/Reels.
  /// 🔥 Hard Fix: Uses global duplicate check to prevent overwriting reactive local state.
  void registerPosts(List<Post> newPosts) {
    batchUpdate(() {
      final currentPosts = _isBatching ? _batchState!.posts : state.posts;
      final updatedPosts = Map<String, Post>.from(currentPosts);
      bool changed = false;

      for (final post in newPosts) {
        if (!updatedPosts.containsKey(post.id)) {
          updatedPosts[post.id] = post;
          changed = true;
        } else {
          // Merge logic: only update fields that aren't usually controlled by local optimistic actions
          // or if the server data is critical (media changes, metadata).
          final existing = updatedPosts[post.id]!;
          updatedPosts[post.id] = existing.copyWith(
            mediaUrl: post.mediaUrl,
            thumbnailUrl: post.thumbnailUrl,
            viewCount: post.viewCount,
            attendeeCount: post.attendeeCount,
            // Only update counts if NO pending local action version is set
            likeCount: _hasPendingAction(post.id, 'like') ? null : post.likeCount,
            commentCount: post.commentCount,
            isLiked: _hasPendingAction(post.id, 'like') ? null : post.isLiked,
            isFollowing: _hasPendingAction(post.id, 'follow') ? null : post.isFollowing,
          );
          changed = true;
        }
      }

      if (changed) {
        final List<String> allIds = updatedPosts.keys.toList();
        _updateState((_isBatching ? _batchState! : state).copyWith(
          posts: updatedPosts,
          postIds: allIds,
        ));
        _checkMemoryLimits();
      }
    });
  }

  bool _hasPendingAction(String postId, String actionType) {
    final versions = _isBatching ? _batchState!.actionVersions : state.actionVersions;
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
    
    _updateState((_isBatching ? _batchState! : state).copyWith(posts: updatedPosts));
  }

  void updatePostPartiallyByAuthor(String authorId, Map<String, dynamic> updates) {
    batchUpdate(() {
      final currentPosts = _isBatching ? _batchState!.posts : state.posts;
      final updatedPosts = Map<String, Post>.from(currentPosts);
      bool changed = false;

      for (final entry in currentPosts.entries) {
        if (entry.value.authorId == authorId) {
          updatedPosts[entry.key] = entry.value.copyWith(
            isFollowing: updates['isFollowing'],
          );
          changed = true;
        }
      }

      if (changed) {
        _updateState((_isBatching ? _batchState! : state).copyWith(posts: updatedPosts));
      }
    });
  }

  void incrementCommentCount(String postId) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;
    final current = currentPosts[postId];
    if (current == null) return;
    updatePostPartially(postId, {'commentCount': current.commentCount + 1});
  }

  void removePost(String postId) {
    final currentPosts = _isBatching ? _batchState!.posts : state.posts;
    final updated = Map<String, Post>.from(currentPosts);
    updated.remove(postId);
    _updateState((_isBatching ? _batchState! : state).copyWith(posts: updated));
  }

  // --- Action Versioning (Race Condition Protection) ---

  void setActionVersion(String postId, String actionType, int version) {
    final currentVersions = _isBatching ? _batchState!.actionVersions : state.actionVersions;
    final versions = Map<String, Map<String, int>>.from(currentVersions);
    final postVersions = Map<String, int>.from(versions[postId] ?? {});
    postVersions[actionType] = version;
    versions[postId] = postVersions;
    _updateState((_isBatching ? _batchState! : state).copyWith(actionVersions: versions));
  }

  // --- Memory Management ---

  void setVisible(String postId, bool visible) {
    final currentVisible = _isBatching ? _batchState!.visibleIds : state.visibleIds;
    final updatedVisible = Set<String>.from(currentVisible);
    if (visible) {
      updatedVisible.add(postId);
    } else {
      updatedVisible.remove(postId);
    }
    _updateState((_isBatching ? _batchState! : state).copyWith(visibleIds: updatedVisible));
  }

  /// Visibility-aware LRU: Keep 100 most recent visible + 400 total cached.
  void _checkMemoryLimits() {
    final currentState = _isBatching ? _batchState! : state;
    if (currentState.posts.length <= 500) return;

    // Sort by creation time (proxy for LRU in this app)
    final sortedIds = currentState.posts.keys.toList()
      ..sort((a, b) => currentState.posts[a]!.createdAt.compareTo(currentState.posts[b]!.createdAt));

    final updatedPosts = Map<String, Post>.from(currentState.posts);
    final updatedVersions = Map<String, Map<String, int>>.from(currentState.actionVersions);
    
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

    _updateState(currentState.copyWith(posts: updatedPosts, actionVersions: updatedVersions));
  }
}

// --- Providers ---

final postStoreProvider = StateNotifierProvider<PostStoreNotifier, PostStoreState>((ref) => PostStoreNotifier());

final postProvider = Provider.family<Post?, String>((ref, postId) {
  return ref.watch(postStoreProvider.select((s) => s.posts[postId]));
});

final postActionVersionProvider = Provider.family<int, (String, String)>((ref, arg) {
  final postId = arg.$1;
  final actionType = arg.$2;
  return ref.watch(postStoreProvider.select((s) => s.actionVersions[postId]?[actionType] ?? 0));
});

// --- Legacy Interop (Mapped to PostStore) ---

final postInteractionProvider = StateNotifierProvider<PostInteractionNotifier, Map<String, Post>>((ref) {
  return PostInteractionNotifier(ref);
});

class PostInteractionNotifier extends StateNotifier<Map<String, Post>> {
  final Ref ref;
  PostInteractionNotifier(this.ref) : super({});

  void initializePost(Post post) {
    ref.read(postStoreProvider.notifier).registerPosts([post]);
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
  CommentCache({required this.comments, required this.lastFetched, this.nextCursor});
}

class CommentCacheNotifier extends StateNotifier<Map<String, CommentCache>> {
  final Ref _ref;
  CommentCacheNotifier(this._ref) : super({});

  Future<void> preload(String postId) async {
    try {
      final response = await BackendService.instance.getComments(postId);
      if (response.success && response.data != null) {
        final comments = (response.data as List).map((c) => Comment.fromJson(c)).toList();
        updateCache(postId, comments, nextCursor: response.pagination?.cursor);
      }
    } catch (_) {}
  }

  void updateCache(String postId, List<Comment> comments, {String? nextCursor, bool isAppend = false}) {
    final existing = state[postId];
    List<Comment> updated = (isAppend && existing != null) ? [...existing.comments, ...comments] : comments;
    state = {...state, postId: CommentCache(comments: updated, lastFetched: DateTime.now(), nextCursor: nextCursor)};
  }

  void addComment(String postId, Comment comment) {
    final existing = state[postId];
    if (existing == null) return;
    state = {...state, postId: CommentCache(comments: [comment, ...existing.comments], lastFetched: existing.lastFetched, nextCursor: existing.nextCursor)};
    _ref.read(postStoreProvider.notifier).incrementCommentCount(postId);
  }
}

final commentCacheProvider = StateNotifierProvider<CommentCacheNotifier, Map<String, CommentCache>>((ref) => CommentCacheNotifier(ref));
