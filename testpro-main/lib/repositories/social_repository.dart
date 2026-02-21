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

  Stream<bool> isPostLikedStream(String postId, String userId) async* {
    final response = await BackendService.checkLikeState(postId);
    if (response.success) {
      yield response.data!['liked'] == true;
    }
  }

  Future<void> toggleFollowUser(String targetUserId) async {
    final response = await BackendService.toggleFollow(targetUserId);
    if (!response.success) throw response.error ?? "Failed to toggle follow";
  }

  Stream<bool> isUserFollowedStream(String userId, String targetUserId) async* {
    final response = await BackendService.checkFollowState(targetUserId);
    if (response.success) {
      yield response.data!;
    }
  }

  Stream<List<UserProfile>> followersStream(String userId) async* {
    // Backend doesn't have a direct "get followers" endpoint yet.
    yield [];
  }

  Stream<List<Post>> likedPostsStream(String userId) async* {
    final response = await BackendService.getPosts(authorId: userId);
    if (response.success) {
      final posts = (response.data as List).map((json) => Post.fromJson(json)).toList();
      yield posts;
    }
  }

  Stream<List<Post>> joinedEventsStream(String userId) async* {
    final response = await BackendService.getPosts(limit: 50);
    if (response.success) {
      final posts = (response.data as List).map((json) => Post.fromJson(json)).toList();
      yield posts;
    }
  }
}
