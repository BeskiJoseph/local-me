import 'package:flutter/foundation.dart';
import '../../models/post.dart';

/// Lightweight feed controller for abstracting mutable list operations
/// mimicking React's reactive state architecture without full Riverpod migration.
class FeedController extends ChangeNotifier {
  final List<Post> _posts = [];
  final Set<String> _tombstones = {}; // Memory layer for optimistic deletions
  
  List<Post> get posts => List.unmodifiable(_posts);
  
  bool isLoading = false;
  bool hasMore = true;
  String? cursor;
  String? error;

  void appendPosts(List<Post> newPosts, {bool refresh = false, String? nextCursor}) {
    if (refresh) {
      _posts.clear();
    }
    
    // Prevent duplicates from rapid pagination AND filter out tombstoned ghost posts
    final existingIds = _posts.map((p) => p.id).toSet();
    final uniqueNew = newPosts.where((p) => 
      !existingIds.contains(p.id) && !_tombstones.contains(p.id)
    ).toList();
    
    _posts.addAll(uniqueNew);
    cursor = nextCursor;
    
    if (_posts.isEmpty && !refresh) {
      hasMore = false;
    } else {
      hasMore = nextCursor != null;
    }
    
    notifyListeners();
  }

  void deletePost(String postId) {
    _tombstones.add(postId);
    _posts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }

  /// Rollback mechanism if actual backend mutation fails
  void restorePost(Post post, {int index = 0}) {
    _tombstones.remove(post.id);
    if (!_posts.any((p) => p.id == post.id)) {
        _posts.insert(index, post);
    }
    notifyListeners();
  }

  void updatePost(Post updatedPost) {
    final index = _posts.indexWhere((p) => p.id == updatedPost.id);
    if (index != -1) {
      _posts[index] = updatedPost;
      notifyListeners();
    }
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
    hasMore = true;
    error = null;
    if (notify) notifyListeners();
  }
}
