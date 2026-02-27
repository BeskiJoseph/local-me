import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/paginated_response.dart';
import '../repositories/post_repository.dart';

enum FeedEventType { postCreated, postDeleted, postLiked, userFollowed, eventMembershipChanged }

class FeedEvent {
  final FeedEventType type;
  final dynamic data;
  FeedEvent(this.type, this.data);
}

/// Facade for [PostRepository].
class PostService {
  static PostRepository _repository = PostRepository();
  
  static final _eventController = StreamController<FeedEvent>.broadcast();
  static Stream<FeedEvent> get events => _eventController.stream;

  static void emit(FeedEvent event) {
    if (kDebugMode) debugPrint('📡 PostService emitting event: ${event.type}');
    _eventController.add(event);
    if (kDebugMode) debugPrint('📡 Event added to stream controller');
  }

  static PostRepository get repository => _repository;

  static set repository(PostRepository repo) {
    _repository = repo;
  }

  /// Creates a new post.
  static Future<String> createPost({
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
    final result = await _repository.createPost(
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
    if (kDebugMode) debugPrint('🔥 Post created with ID: $result');
    emit(FeedEvent(FeedEventType.postCreated, result));
    if (kDebugMode) debugPrint('📧 FeedEvent emitted for post creation');
    return result;
  }

  static Future<void> deletePost(String postId) async {
    await _repository.deletePost(postId);
    emit(FeedEvent(FeedEventType.postDeleted, postId));
  }

  static Stream<List<Post>> postsByScope(String scope) {
    return _repository.postsByScope(scope);
  }

  static Future<PaginatedResponse<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    String? afterId,
    int limit = 10,
  }) {
    return _repository.getPostsPaginated(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
      afterId: afterId,
      limit: limit,
    );
  }

  static Stream<List<Post>> postsForFeed({
    required String feedType,
    String? userCity,
    String? userCountry,
  }) {
    return _repository.postsForFeed(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
    );
  }

  static Stream<List<Post>> postsByAuthor(String authorId) {
    return _repository.postsByAuthor(authorId);
  }

  // --- Event Related Methods ---

  static Stream<int> eventAttendeesCountStream(String eventId) {
    return _repository.eventAttendeesCountStream(eventId);
  }

  static Future<void> toggleEventAttendance(String eventId, String userId) {
    return _repository.toggleEventAttendance(eventId, userId).then((_) {
      emit(FeedEvent(FeedEventType.eventMembershipChanged, eventId));
    });
  }

  static Future<String> createEvent({
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
    final createdEventId = await _repository.createEvent(
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
    emit(FeedEvent(FeedEventType.postCreated, createdEventId));
    return createdEventId;
  }
  static Stream<bool> isAttendingEventStream(String eventId, String userId) {
    return _repository.isAttendingEventStream(eventId, userId);
  }
}

