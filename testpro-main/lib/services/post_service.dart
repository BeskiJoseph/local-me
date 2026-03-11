import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../models/paginated_response.dart';
import '../repositories/post_repository.dart';
import '../services/location_service.dart';

enum FeedEventType { postCreated, postDeleted, postUpdated, postLiked, commentAdded, userFollowed, eventMembershipChanged }

class FeedEvent {
  final FeedEventType type;
  final dynamic data;
  FeedEvent(this.type, this.data);
}

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
  
  static final _eventController = StreamController<FeedEvent>.broadcast();
  static Stream<FeedEvent> get events => _eventController.stream;

  // Session interaction cache — ensures likes/comments survive refresh
  static final Map<String, _PostInteraction> _interactionCache = {};

  // Hidden initializer for the sync listener
  static final bool _initialized = _initSyncListener();

  static bool _initSyncListener() {
    events.listen((event) {
      if (event.type == FeedEventType.postLiked) {
        final data = event.data as Map<String, dynamic>;
        final id = data['postId']?.toString();
        if (id == null) return;
        final existing = _interactionCache[id] ?? const _PostInteraction();
        _interactionCache[id] = existing.merge(_PostInteraction(
          isLiked: data['isLiked'],
          likeCount: data['likeCount'],
        ));
      } else if (event.type == FeedEventType.commentAdded) {
        final data = event.data as Map<String, dynamic>;
        final id = data['postId']?.toString();
        if (id == null) return;
        final existing = _interactionCache[id] ?? const _PostInteraction();
        _interactionCache[id] = existing.merge(_PostInteraction(
          commentCount: data['commentCount'],
        ));
      }
    });
    return true;
  }

  static void emit(FeedEvent event) {
    // Ensure initialized
    if (!_initialized) {}
    if (kDebugMode) debugPrint('📡 PostService emitting event: ${event.type}');
    _eventController.add(event);
  }

  static PostRepository get repository => _repository;

  static set repository(PostRepository repo) {
    _repository = repo;
  }

  /// Overlay session interactions onto fresh API data
  static Post mergeInteractions(Post post) {
    // Ensure initialized
    if (!_initialized) {}
    final cached = _interactionCache[post.id];
    if (cached == null) return post;
    return post.copyWith(
      isLiked: cached.isLiked ?? post.isLiked,
      likeCount: cached.likeCount ?? post.likeCount,
      commentCount: cached.commentCount ?? post.commentCount,
    );
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
    emit(FeedEvent(FeedEventType.postCreated, result));
    return result;
  }

  static Future<void> deletePost(String postId) async {
    await _repository.deletePost(postId);
    emit(FeedEvent(FeedEventType.postDeleted, postId));
  }

  static Future<void> updatePost(String postId, Map<String, dynamic> updates) async {
    await _repository.updatePost(postId, updates);
    emit(FeedEvent(FeedEventType.postUpdated, {'postId': postId, 'updates': updates}));
  }

  static Future<PaginatedResponse<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    String? afterId,
    double? lastDistance,
    String? lastPostId,
    String? watchedIds,
    String? authorId,
    String? category,
    String? mediaType,
    int limit = 10,
  }) async {
    final response = await _repository.getPostsPaginated(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
      afterId: afterId,
      lastDistance: lastDistance,
      lastPostId: lastPostId,
      watchedIds: watchedIds,
      authorId: authorId,
      category: category,
      mediaType: mediaType,
      limit: limit,
    );
    
    // Transparently merge session interactions before returning
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
    return _repository.postsByAuthor(authorId).map((list) => list.map(mergeInteractions).toList());
  }

  static Stream<List<Post>> postsByScope(String scope) {
    return _repository.postsByScope(scope).map((list) => list.map(mergeInteractions).toList());
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

  // Adding Location proxy for PaginatedFeedList since it expects it
  static Future<dynamic> getCurrentPosition() async {
    return LocationService.currentPosition;
  }
}
