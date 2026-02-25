import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/backend_service.dart';

/// Repository for handling Social Interactions (Likes, Follows).
class SocialRepository {
  SocialRepository();

  Future<void> toggleLikePost(String postId, String userId) async {
    final response = await BackendService.toggleLike(postId);
    if (!response.success) throw response.error ?? "Failed to toggle like";
  }

  /// Returns a single-boolean stream for like state.
  /// NOTE: This creates a new API call every time it's called.
  /// Consider caching the result in the widget layer.
  Stream<bool> isPostLikedStream(String postId, String userId) async* {
    final response = await BackendService.checkLikeState(postId);
    if (response.success) {
      yield response.data!['liked'] == true;
    }
  }
  
  /// Future version - use this when you only need the value once
  Future<bool> isPostLiked(String postId, String userId) async {
    final response = await BackendService.checkLikeState(postId);
    if (response.success) {
      return response.data!['liked'] == true;
    }
    return false;
  }

  Future<void> toggleFollowUser(String targetUserId) async {
    final response = await BackendService.toggleFollow(targetUserId);
    if (!response.success) throw response.error ?? "Failed to toggle follow";
  }

  /// Returns a single-boolean stream for follow state.
  /// NOTE: This creates a new API call every time it's called.
  /// Consider caching the result in the widget layer.
  Stream<bool> isUserFollowedStream(String userId, String targetUserId) async* {
    final response = await BackendService.checkFollowState(targetUserId);
    if (response.success) {
      yield response.data!;
    }
  }
  
  /// Future version - use this when you only need the value once
  Future<bool> isUserFollowed(String userId, String targetUserId) async {
    final response = await BackendService.checkFollowState(targetUserId);
    if (response.success) {
      return response.data!;
    }
    return false;
  }

  Stream<List<UserProfile>> followersStream(String userId) async* {
    // Backend doesn't have a direct "get followers" endpoint yet.
    yield [];
  }

  Stream<List<Post>> likedPostsStream(String userId) async* {
    final response = await BackendService.getPosts(authorId: userId);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      yield posts;
    }
  }

  Stream<List<Post>> joinedEventsStream(String userId) async* {
    final response = await BackendService.getPosts(limit: 50);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      yield posts;
    }
  }
}
