import '../models/post.dart';
import '../models/user_profile.dart';
import '../repositories/social_repository.dart';

/// Facade for [SocialRepository].
class SocialService {
  static SocialRepository _repository = SocialRepository();
  
  static SocialRepository get repository => _repository;
  
  static set repository(SocialRepository repo) => _repository = repo;

  static Future<void> toggleLikePost(String postId, String userId) {
    return _repository.toggleLikePost(postId, userId);
  }

  static Stream<bool> isPostLikedStream(String postId, String userId) {
    return _repository.isPostLikedStream(postId, userId);
  }
  
  static Future<bool> isPostLiked(String postId, String userId) {
    return _repository.isPostLiked(postId, userId);
  }

  static Future<void> toggleFollowUser(String targetUserId) {
    return _repository.toggleFollowUser(targetUserId);
  }

  static Stream<List<UserProfile>> followersStream(String userId) {
    return _repository.followersStream(userId);
  }

  static Stream<bool> isUserFollowedStream(String userId, String targetUserId) {
    return _repository.isUserFollowedStream(userId, targetUserId);
  }
  
  static Future<bool> isUserFollowed(String userId, String targetUserId) {
    return _repository.isUserFollowed(userId, targetUserId);
  }

  static Stream<List<Post>> likedPostsStream(String userId) {
    return _repository.likedPostsStream(userId);
  }

  static Stream<List<Post>> joinedEventsStream(String userId) {
    return _repository.joinedEventsStream(userId);
  }
}
