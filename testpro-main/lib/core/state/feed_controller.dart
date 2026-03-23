import 'package:flutter/foundation.dart';
import '../../models/post.dart';
import 'feed_session.dart';

/// Lightweight feed controller for abstracting mutable list operations
class FeedController extends ChangeNotifier {
  final String feedType;
  final List<Post> _posts = [];
  final Set<String> _tombstones = {}; // Memory layer for optimistic deletions
  // Local feed state moved to seenIds-based flow; remove distance cursor state

  FeedController({this.feedType = 'global'});

  List<Post> get posts => List.unmodifiable(_posts);
  bool isLoading = false;
  bool hasMore = true;
  String? error;
  bool isCycling = false;

  void appendPosts(
    List<Post> newPosts, {
    bool refresh = false,
    bool isHistorical = true, // ✅ New flag
    bool? hasMore, // provided by repo
  }) {
    if (refresh) {
      _posts.clear();
      // reset state for new session
      isCycling = false;
      hasMore = true; // Reset hasMore on refresh
    }

    // Prevent duplicates from rapid pagination AND filter out tombstoned ghost posts
    final existingIds = _posts.map((p) => p.id).toSet();
    final uniqueNew = newPosts
        .where(
          (p) => !existingIds.contains(p.id) && !_tombstones.contains(p.id),
        )
        .toList();

    _posts.addAll(uniqueNew);

    // Update pagination state
    if (hasMore != null) this.hasMore = hasMore;

    // Post-shipment: rely on provided hasMore flag from repo when available

    if (this.hasMore == false && !isCycling && _posts.length >= 10) {
      isCycling = true;
      this.hasMore = true; // Allow loading from the beginning
      FeedSession.instance.reset(
        feedType,
      ); // Transparently reset seen state for cycling
    }

    notifyListeners();
  }

  void deletePost(String postId) {
    _tombstones.add(postId);
    _posts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }

  void updatePostLike(String postId, bool? isLiked, int likeCount) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _posts[index] = _posts[index].copyWith(
        isLiked: isLiked,
        likeCount: likeCount,
      );
      notifyListeners();
    }
  }

  void updatePostCommentCount(String postId, int commentCount) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      _posts[index] = _posts[index].copyWith(commentCount: commentCount);
      notifyListeners();
    }
  }

  void updatePost(String postId, Map<String, dynamic> updates) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) {
      final current = _posts[index];
      _posts[index] = current.copyWith(
        title: updates['title'] ?? current.title,
        body: updates['body'] ?? updates['text'] ?? current.body,
        category: updates['category'] ?? current.category,
        city: updates['city'] ?? current.city,
        country: updates['country'] ?? current.country,
      );
      notifyListeners();
    }
  }

  void prependPost(Post post) {
    if (!_posts.any((p) => p.id == post.id)) {
      _posts.insert(0, post);
      notifyListeners();
    }
  }

  void injectNewPosts(List<Post> newPosts) {
    bool changed = false;
    for (final newPost in newPosts) {
      if (_posts.any((p) => p.id == newPost.id)) continue;
      if (_tombstones.contains(newPost.id)) continue;

      // Find the correct insertion point based on distance
      final insertIndex = _posts.indexWhere(
        (p) => (p.distance ?? 999999) > (newPost.distance ?? 999999),
      );

      if (insertIndex == -1) {
        _posts.add(newPost);
      } else {
        _posts.insert(insertIndex, newPost);
      }
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setLoading(bool loading) {
    isLoading = loading;
    notifyListeners();
  }

  void setError(String? errorMessage) {
    error = errorMessage;
    notifyListeners();
  }

  void prependPosts(List<Post> newPosts) {
    if (newPosts.isEmpty) return;

    final existingIds = _posts.map((p) => p.id).toSet();
    final uniqueNew = newPosts
        .where(
          (p) => !existingIds.contains(p.id) && !_tombstones.contains(p.id),
        )
        .toList();

    _posts.insertAll(0, uniqueNew);
    notifyListeners();
  }

  /// Injects posts at a specific index (usually current visible index)
  /// to avoid making the user re-scroll through already seen content.
  void insertAtVisiblePosition(List<Post> newPosts, int index) {
    if (newPosts.isEmpty) return;

    final existingIds = _posts.map((p) => p.id).toSet();
    final uniqueNew = newPosts
        .where(
          (p) => !existingIds.contains(p.id) && !_tombstones.contains(p.id),
        )
        .toList();

    if (uniqueNew.isEmpty) return;

    // Clamp index to safe bounds
    final targetIndex = index.clamp(0, _posts.length);
    _posts.insertAll(targetIndex, uniqueNew);
    notifyListeners();
  }

  void clear({bool notify = true}) {
    _posts.clear();
    // reset seen-based flow state
    hasMore = true;
    error = null;
    isCycling = false;
    if (notify) notifyListeners();
  }
}
