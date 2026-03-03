import 'package:flutter/foundation.dart';
import '../../models/post.dart';

/// Lightweight feed controller for abstracting mutable list operations
class FeedController extends ChangeNotifier {
  final List<Post> _posts = [];
  final Set<String> _tombstones = {}; // Memory layer for optimistic deletions
  
  // Local feed distance cursors
  double lastDistance = 0.0;
  String? lastPostId;
  
  List<Post> get posts => List.unmodifiable(_posts);
  bool isLoading = false;
  bool hasMore = true;
  String? cursor; // afterId for global feed
  String? error;
  bool isCycling = false;

  void appendPosts(List<Post> newPosts, {
    bool refresh = false, 
    String? nextCursor,
    double? newLastDistance,
    String? newLastPostId,
    String? fallbackLevel,
  }) {
    if (refresh) {
      _posts.clear();
      lastDistance = 0.0;
      lastPostId = null;
      isCycling = false;
    }
    
    // Prevent duplicates from rapid pagination AND filter out tombstoned ghost posts
    final existingIds = _posts.map((p) => p.id).toSet();
    final uniqueNew = newPosts.where((p) => 
      !existingIds.contains(p.id) && !_tombstones.contains(p.id)
    ).toList();
    
    _posts.addAll(uniqueNew);
    
    // Update cursors
    cursor = nextCursor;
    if (newLastDistance != null) lastDistance = newLastDistance;
    if (newLastPostId != null) lastPostId = newLastPostId;
    
    if (_posts.isEmpty && !refresh) {
      hasMore = false;
    } else {
      // Local feed uses distance cursor, so nextCursor (afterId) might be null
      // But we determine hasMore from the API response's metadata
      hasMore = nextCursor != null || (newLastPostId != null);
    }
    
    if (fallbackLevel == 'cycle') {
      isCycling = true;
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
        (p) => (p.distance ?? 999999) > (newPost.distance ?? 999999)
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

  void clear({bool notify = true}) {
    _posts.clear();
    cursor = null;
    lastDistance = 0.0;
    lastPostId = null;
    hasMore = true;
    error = null;
    isCycling = false;
    if (notify) notifyListeners();
  }
}
