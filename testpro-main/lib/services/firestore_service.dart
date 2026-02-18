import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../models/user_profile.dart';
import '../models/signup_data.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import '../models/chat_message.dart';

import 'post_service.dart';
import 'user_service.dart';
import 'social_service.dart';
import 'feed_service.dart';
import 'comment_service.dart';
import 'search_service.dart';
import 'chat_service.dart';
import 'notification_data_service.dart';

/// Facade for backward compatibility.
/// Delegates all calls to specialized services.
class FirestoreService {
  // Recommendation Weights (V3)
  static const double weightWatchTime = FeedService.weightWatchTime;
  static const double weightLike = FeedService.weightLike;
  static const double weightComment = FeedService.weightComment;
  static const double weightShare = FeedService.weightShare;
  static const double weightSkipPenalty = FeedService.weightSkipPenalty;

  /// Logs user behavior with support for negative signals and sessions
  static Future<void> logUserActivity({
    required String userId,
    required String postId,
    required String category,
    required List<String> tags,
    double watchTime = 0,
    bool liked = false,
    bool commented = false,
    bool shared = false,
    String? sessionId,
  }) {
    return FeedService.logUserActivity(
      userId: userId,
      postId: postId,
      category: category,
      tags: tags,
      watchTime: watchTime,
      liked: liked,
      commented: commented,
      shared: shared,
      sessionId: sessionId,
    );
  }

  /// Fetches a personalized feed using the V3 Mix Strategy
  static Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) {
    return FeedService.getRecommendedFeed(
      userId: userId,
      sessionId: sessionId,
      lastDocument: lastDocument,
      limit: limit,
    );
  }

  static Stream<List<Post>> postsByScope(String scope) {
    return PostService.postsByScope(scope);
  }

  static Future<List<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) {
    return PostService.getPostsPaginated(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
      lastDocument: lastDocument,
      limit: limit,
    );
  }

  static Stream<List<Post>> postsForFeed({
    required String feedType,
    String? userCity,
    String? userCountry,
  }) {
    return PostService.postsForFeed(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
    );
  }

  static Stream<List<Post>> postsByAuthor(String authorId) {
    return PostService.postsByAuthor(authorId);
  }

  static Stream<UserProfile?> userProfileStream(String userId) {
    return UserService.userProfileStream(userId);
  }

  static Future<UserProfile?> getUserProfile(String userId) {
    return UserService.getUserProfile(userId);
  }

  static Future<void> createUserProfile({
    required User user,
    required SignupData data,
    String? profileImageUrl,
  }) {
    return UserService.createUserProfile(
      user: user,
      data: data,
      profileImageUrl: profileImageUrl,
    );
  }

  static Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? about,
    String? profileImageUrl,
  }) {
    return UserService.updateUserProfile(
      userId: userId,
      displayName: displayName,
      about: about,
      profileImageUrl: profileImageUrl,
    );
  }

  static Future<void> syncGoogleUser(User user) {
    return UserService.syncGoogleUser(user);
  }

  static Future<void> incrementContentCount(String userId) {
    return UserService.incrementContentCount(userId);
  }

  static Future<void> recalculateUserStats(String userId) {
    return UserService.recalculateUserStats(userId);
  }

  static Future<String> createPost({
    required String authorId,
    required String authorName,
    required String title,
    required String body,
    String scope = 'local',
    double? latitude,
    double? longitude,
    String? city,
    String? country,
    String category = 'General',
    String? mediaUrl,
    String mediaType = 'image',
    String? thumbnailUrl,
    String? authorProfileImage,
  }) {
    return PostService.createPost(
      authorId: authorId,
      authorName: authorName,
      title: title,
      body: body,
      scope: scope,
      latitude: latitude,
      longitude: longitude,
      city: city,
      country: country,
      category: category,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      thumbnailUrl: thumbnailUrl,
      authorProfileImage: authorProfileImage,
    );
  }

  static Future<void> deletePost(String postId) {
    return PostService.deletePost(postId);
  }

  static Future<void> toggleLikePost(String postId, String userId, {String? category, List<String>? tags}) {
    return SocialService.toggleLikePost(postId, userId, category: category, tags: tags);
  }

  static Future<void> setPostLike(String postId, String userId, bool shouldLike) {
    return SocialService.setPostLike(postId, userId, shouldLike);
  }

  static Stream<bool> isPostLikedStream(String postId, String userId) {
    return SocialService.isPostLikedStream(postId, userId);
  }

  static Future<void> followUser(String currentUserId, String targetUserId) {
    return SocialService.followUser(currentUserId, targetUserId);
  }

  static Future<void> unfollowUser(String currentUserId, String targetUserId) {
    return SocialService.unfollowUser(currentUserId, targetUserId);
  }

  static Stream<List<UserProfile>> followersStream(String userId) {
    return SocialService.followersStream(userId);
  }

  static Stream<bool> isUserFollowedStream(String currentUserId, String targetUserId) {
    return SocialService.isUserFollowedStream(currentUserId, targetUserId);
  }

  static Stream<List<Comment>> commentsStream(String postId) {
    return CommentService.commentsStream(postId);
  }

  static Future<void> addComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorProfileImage,
    required String text,
  }) {
    return CommentService.addComment(
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorProfileImage: authorProfileImage,
      text: text,
    );
  }

  // Instance methods (Legacy API consistency)
  Stream<QuerySnapshot> searchUsers(String query) {
    return SearchService.searchUsers(query);
  }

  Stream<QuerySnapshot> searchPosts(String query) {
    return SearchService.searchPosts(query);
  }

  Stream<QuerySnapshot> getPostsStream() {
    return PostService.getPostsStream();
  }

  static Stream<int> eventAttendeesCountStream(String eventId) {
    return PostService.eventAttendeesCountStream(eventId);
  }

  static Stream<bool> isAttendingEventStream(String eventId, String userId) {
    return PostService.isAttendingEventStream(eventId, userId);
  }

  static Future<void> toggleEventAttendance(String eventId, String userId) {
    return PostService.toggleEventAttendance(eventId, userId);
  }

  static Future<void> createEvent({
    required String authorId,
    required String authorName,
    String? authorProfileImage,
    required String title,
    required String description,
    required String eventType,
    required DateTime eventDate,
    required String location,
    required double latitude,
    required double longitude,
    required String city,
    required String country,
    String? mediaUrl,
    bool isFree = true,
  }) {
    return PostService.createEvent(
      authorId: authorId,
      authorName: authorName,
      authorProfileImage: authorProfileImage,
      title: title,
      description: description,
      eventType: eventType,
      eventDate: eventDate,
      location: location,
      latitude: latitude,
      longitude: longitude,
      city: city,
      country: country,
      mediaUrl: mediaUrl,
      isFree: isFree,
    );
  }

  static Stream<List<Post>> likedPostsStream(String userId) {
    return SocialService.likedPostsStream(userId);
  }

  static Stream<List<ActivityNotification>> notificationsStream(String userId) {
    return NotificationDataService.notificationsStream(userId);
  }

  static Future<void> markNotificationAsRead(String notificationId) {
    return NotificationDataService.markNotificationAsRead(notificationId);
  }

  // Note: _sendNotification was private, but exposed conceptually via actions. 
  // If it was used externally, we'd need to expose it. 
  // It seems it was only used internally. 
  // We can expose it for rigorousness if needed, but it was private.

  static Stream<List<Post>> joinedEventsStream(String userId) {
    return SocialService.joinedEventsStream(userId);
  }

  static Stream<List<ChatMessage>> messagesStream(String eventId) {
    return ChatService.messagesStream(eventId);
  }

  static Future<void> sendChatMessage(String eventId, ChatMessage message) {
    return ChatService.sendChatMessage(eventId, message);
  }
}
