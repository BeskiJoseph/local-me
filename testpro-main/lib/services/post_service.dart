import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/models/paginated_response.dart';
import 'package:testpro/repositories/post_repository.dart';
import 'package:testpro/services/location_service.dart';
import 'package:testpro/core/state/feed_session.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/core/state/provider_container.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'backend_service.dart';

class _PostInteraction {
  final bool? isLiked;
  final int? likeCount;
  final int? commentCount;

  const _PostInteraction({this.isLiked, this.likeCount, this.commentCount});

  _PostInteraction merge(_PostInteraction other) => _PostInteraction(
    isLiked: other.isLiked ?? isLiked,
    likeCount: other.likeCount ?? likeCount,
    commentCount: other.commentCount ?? commentCount,
  );
}

/// Facade for [PostRepository].
class PostService {
  static PostRepository _repository = PostRepository();

  // Session interaction cache — ensures likes/comments survive refresh
  static final Map<String, _PostInteraction> _interactionCache = {};


  static PostRepository get repository => _repository;

  static set repository(PostRepository repo) {
    _repository = repo;
  }

  static Post mergeInteractions(Post post) {
    final cached = _interactionCache[post.id];
    if (cached == null) return post;
    return post.copyWith(
      isLiked: cached.isLiked ?? post.isLiked,
      likeCount: cached.likeCount ?? post.likeCount,
      commentCount: cached.commentCount ?? post.commentCount,
    );
  }

  /// Creates a new post.
  static Future<Post> createPost({
    required String title,
    required String body,
    String scope = 'local',
    double? latitude,
    double? longitude,
    String? city,
    String? country,
    String category = 'General',
    String? mediaUrl,
    String mediaType = 'none',
    String? thumbnailUrl,
  }) async {
    final post = await _repository.createPost(
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
    );
    return post;
  }

  static Future<void> deletePost(String postId) async {
    await _repository.deletePost(postId);
  }

  static Future<void> updatePost(
    String postId,
    Map<String, dynamic> updates,
  ) async {
    await _repository.updatePost(postId, updates);
  }

  static Future<PaginatedResponse<Post>> getPostsPaginated({
    required String feedType,
    int? limit,
    Map<String, dynamic>? lastCursors,
    String? mediaType,
    double? latitude,
    double? longitude,
    String? userCity,
    String? userCountry,
  }) async {
    final response = await _repository.getPostsPaginated(
      feedType: feedType,
      limit: limit ?? 15,
      lastCursors: lastCursors,
      mediaType: mediaType,
      latitude: latitude,
      longitude: longitude,
      userCity: userCity,
      userCountry: userCountry,
    );

    // Transparently merge session interactions before returning
    final mergedPosts = response.data.map(mergeInteractions).toList();
    return response.copyWith(data: mergedPosts);
  }

  /// Dedicated method for filtered results (Author, Category, etc.)
  /// This keeps the main getPostsPaginated pure and stateless.
  static Future<PaginatedResponse<Post>> getFilteredPostsPaginated({
    String? authorId,
    String? category,
    String? city,
    String? country,
    int limit = 15,
    Map<String, dynamic>? lastCursors,
  }) async {
    final response = await _repository.getFilteredPostsPaginated(
      authorId: authorId,
      category: category,
      city: city,
      country: country,
      limit: limit,
      lastCursors: lastCursors,
    );

    final mergedPosts = response.data.map(mergeInteractions).toList();
    return response.copyWith(data: mergedPosts);
  }

  static Future<PaginatedResponse<Post>> getExplorePosts({int limit = 30}) async {
    final response = await _repository.getExplorePosts(limit: limit);
    final mergedPosts = response.data.map(mergeInteractions).toList();
    return response.copyWith(data: mergedPosts);
  }

  static Future<Post?> getPost(String postId) async {
    final response = await _repository.getPost(postId);
    if (response.success && response.data != null) {
      return mergeInteractions(Post.fromJson(response.data!));
    }
    return null;
  }

  static Stream<List<Post>> postsByAuthor(String authorId) {
    return _repository
        .postsByAuthor(authorId)
        .map((list) => list.map(mergeInteractions).toList());
  }

  static Stream<List<Post>> postsByScope(String scope) {
    return _repository
        .postsByScope(scope)
        .map((list) => list.map(mergeInteractions).toList());
  }

  // --- Event Related Methods ---
  static Stream<int> eventAttendeesCountStream(String eventId) {
    return _repository.eventAttendeesCountStream(eventId);
  }

  static Future<void> toggleEventAttendance(String eventId, String userId) {
    return _repository.toggleEventAttendance(eventId, userId);
  }

  static Future<Post> createEvent({
    required String title,
    required String description,
    required String eventType,
    required DateTime eventStartDate,
    required DateTime eventEndDate,
    required String location,
    double? latitude,
    double? longitude,
    required String city,
    required String country,
    String? mediaUrl,
    bool isFree = true,
  }) async {
    final post = await _repository.createEvent(
      title: title,
      description: description,
      eventType: eventType,
      eventStartDate: eventStartDate,
      eventEndDate: eventEndDate,
      location: location,
      latitude: latitude,
      longitude: longitude,
      city: city,
      country: country,
      mediaUrl: mediaUrl,
      isFree: isFree,
    );
    return post;
  }

  static Stream<bool> isAttendingEventStream(String eventId, String userId) {
    return _repository.isAttendingEventStream(eventId, userId);
  }

  // Adding Location proxy for PaginatedFeedList since it expects it
  static Future<dynamic> getCurrentPosition() async {
    return LocationService.currentPosition;
  }
}
