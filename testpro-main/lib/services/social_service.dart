import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../repositories/social_repository.dart';

/// Facade for [SocialRepository].
/// Provides static access to social interaction operations.
class SocialService {
  static SocialRepository _repository = SocialRepository();
  
  static SocialRepository get repository => _repository;
  
  static set repository(SocialRepository repo) => _repository = repo;

  static Future<void> toggleLikePost(String postId, String userId, {String? category, List<String>? tags}) {
    return _repository.toggleLikePost(postId, userId, category: category, tags: tags);
  }

  static Future<void> setPostLike(String postId, String userId, bool shouldLike) {
    return _repository.setPostLike(postId, userId, shouldLike);
  }

  static Stream<bool> isPostLikedStream(String postId, String userId) {
    return _repository.isPostLikedStream(postId, userId);
  }

  static Future<void> followUser(String currentUserId, String targetUserId) {
    return _repository.followUser(currentUserId, targetUserId);
  }

  static Future<void> unfollowUser(String currentUserId, String targetUserId) {
    return _repository.unfollowUser(currentUserId, targetUserId);
  }

  static Stream<List<UserProfile>> followersStream(String userId) {
    return _repository.followersStream(userId);
  }

  static Stream<bool> isUserFollowedStream(String currentUserId, String targetUserId) {
    return _repository.isUserFollowedStream(currentUserId, targetUserId);
  }

  static Stream<List<Post>> likedPostsStream(String userId) {
    return _repository.likedPostsStream(userId);
  }

  static Stream<List<Post>> joinedEventsStream(String userId) {
    return _repository.joinedEventsStream(userId);
  }
}
