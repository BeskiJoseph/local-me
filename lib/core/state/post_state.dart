import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:collection';

// Minimalistic models (shared for Phase 5 patch compatibility)
class Comment {
  final String id;
  final String authorId;
  final String text;
  final DateTime createdAt;
  Comment({
    required this.id,
    required this.authorId,
    required this.text,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class Post {
  final String id;
  final String content;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final List<Comment> comments;
  Post({
    required this.id,
    required this.content,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.comments = const [],
  });
  Post copyWith({
    String? id,
    String? content,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    List<Comment>? comments,
  }) {
    return Post(
      id: id ?? this.id,
      content: content ?? this.content,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      comments: comments ?? this.comments,
    );
  }
}

class PostStoreState {
  final Map<String, Post> posts;
  final Map<String, Map<String, int>> actionVersions;
  final List<String> postIds;
  final Set<String> visiblePostIds;

  const PostStoreState({
    required this.posts,
    required this.actionVersions,
    this.postIds = const [],
    this.visiblePostIds = const <String>{},
  });

  PostStoreState copyWith({
    Map<String, Post>? posts,
    Map<String, Map<String, int>>? actionVersions,
    List<String>? postIds,
    Set<String>? visiblePostIds,
  }) {
    return PostStoreState(
      posts: posts ?? this.posts,
      actionVersions: actionVersions ?? this.actionVersions,
      postIds: postIds ?? this.postIds,
      visiblePostIds: visiblePostIds ?? this.visiblePostIds,
    );
  }
}

class PostStore extends StateNotifier<PostStoreState> {
  static const int _maxPosts = 500;
  PostStore()
    : super(
        PostStoreState(
          posts: {},
          actionVersions: {},
          postIds: [],
          visiblePostIds: <String>{},
        ),
      );

  Post? getPost(String postId) => state.posts[postId];
  UnmodifiableMapView<String, Post> get posts =>
      UnmodifiableMapView(state.posts);
  List<String> get postIds => state.postIds;

  void markVisible(String postId) {
    if (state.visiblePostIds.contains(postId)) return;
    final updated = Set<String>.from(state.visiblePostIds)..add(postId);
    state = state.copyWith(visiblePostIds: updated);
  }

  void markInvisible(String postId) {
    if (!state.visiblePostIds.contains(postId)) return;
    final updated = Set<String>.from(state.visiblePostIds)..remove(postId);
    state = state.copyWith(visiblePostIds: updated);
  }

  void registerPosts(List<Post> newPosts) {
    final updatedPosts = {...state.posts};
    final updatedIds = [...state.postIds];
    for (final p in newPosts) {
      if (!updatedPosts.containsKey(p.id)) {
        updatedPosts[p.id] = p;
        updatedIds.add(p.id);
      } else {
        final exists = updatedPosts[p.id]!;
        updatedPosts[p.id] = exists.copyWith(
          likeCount: p.likeCount,
          commentCount: p.commentCount,
          isLiked: p.isLiked,
          comments: p.comments.isNotEmpty ? p.comments : exists.comments,
        );
      }
    }
    const maxPosts = _maxPosts;
    if (updatedIds.length > maxPosts) {
      final removable = updatedIds
          .where((id) => !state.visiblePostIds.contains(id))
          .toList();
      if (removable.isNotEmpty) {
        final toRemove = removable.take(updatedIds.length - maxPosts);
        for (final id in toRemove) {
          updatedPosts.remove(id);
          updatedIds.remove(id);
        }
      } else {
        final toRemove = updatedIds.take(5);
        for (final id in toRemove) updatedPosts.remove(id);
        updatedIds.removeRange(0, 5);
      }
    }
    state = state.copyWith(posts: updatedPosts, postIds: updatedIds);
  }

  void updatePost(String postId, Post Function(Post) updater) {
    final existing = state.posts[postId];
    if (existing == null) return;
    final updated = updater(existing);
    final next = Map<String, Post>.from(state.posts);
    next[postId] = updated;
    state = state.copyWith(posts: next);
  }

  void toggleLike(String postId) {
    final p = state.posts[postId];
    if (p == null) return;
    final updated = p.copyWith(
      isLiked: !p.isLiked,
      likeCount: p.likeCount + (p.isLiked ? -1 : 1),
    );
    final next = Map<String, Post>.from(state.posts);
    next[postId] = updated;
    state = state.copyWith(posts: next);
    _bumpActionVersion('like', postId);
  }

  void addComment(String postId, Comment comment) {
    final p = state.posts[postId];
    if (p == null) return;
    final isDuplicate = p.comments.any((c) => c.id == comment.id);
    final newComments = isDuplicate ? p.comments : [comment, ...p.comments];
    final updated = p.copyWith(
      commentCount: p.commentCount + (isDuplicate ? 0 : 1),
      comments: newComments,
    );
    final next = Map<String, Post>.from(state.posts);
    next[postId] = updated;
    state = state.copyWith(posts: next);
    _bumpActionVersion('comment', postId);
  }

  void _bumpActionVersion(String action, String postId) {
    final current = state.actionVersions[action] ?? {};
    final nextForAction = Map<String, int>.from(current);
    nextForAction[postId] = (nextForAction[postId] ?? 0) + 1;
    final nextVersions = Map<String, Map<String, int>>.from(
      state.actionVersions,
    );
    nextVersions[action] = nextForAction;
    state = state.copyWith(actionVersions: nextVersions);
  }

  void batchUpdate(List<void Function(PostStore)?> updates) {
    for (final fn in updates) if (fn != null) fn(this);
  }
}

final postStoreProvider = StateNotifierProvider<PostStore, PostStoreState>(
  (ref) => PostStore(),
);

final postProvider = Provider.family<Post?, String>((ref, postId) {
  final store = ref.watch(postStoreProvider);
  return store.posts[postId];
});
