import 'package:testpro/models/post.dart';
import 'package:testpro/models/paginated_response.dart';
import 'package:testpro/models/api_response.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/location_service.dart';

/// Repository for handling Post and Event data operations.
/// V2: Strict distance-cursor pagination + session-level deduplication.
class PostRepository {
  PostRepository();

  // ─────────────────────────────────────────────
  // Create Post
  // ─────────────────────────────────────────────
  Future<Post> createPost({
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
    final response = await BackendService.createPost({
      'title': title,
      'body': body,
      'text': '$title\n$body'.trim(),
      'category': category,
      'city': city,
      'country': country,
      'mediaUrl': mediaUrl,
      'mediaType': (mediaUrl == null || mediaUrl.isEmpty) ? 'none' : mediaType,
      'thumbnailUrl': thumbnailUrl,
      'location': (latitude != null && longitude != null)
          ? {'lat': latitude, 'lng': longitude, 'name': city ?? 'Unknown'}
          : null,
      'tags': [category],
    });

    if (!response.success || response.data == null)
      throw response.error ?? 'Failed to create post';
    return Post.fromJson(response.data!);
  }

  // ─────────────────────────────────────────────
  // Delete Post
  // ─────────────────────────────────────────────
  Future<void> deletePost(String postId) async {
    final response = await BackendService.deletePost(postId);
    if (!response.success) throw response.error ?? 'Failed to delete post';
  }

  // ─────────────────────────────────────────────
  // Update Post
  // ─────────────────────────────────────────────
  Future<void> updatePost(String postId, Map<String, dynamic> updates) async {
    final response = await BackendService.updatePost(postId, updates);
    if (!response.success) throw response.error ?? 'Failed to update post';
  }

  Future<PaginatedResponse<Post>> getPostsPaginated({
    required String feedType,
    int limit = 15,
    Map<String, dynamic>? lastCursors,
    String? mediaType,
    double? latitude,
    double? longitude,
    String? userCity,
    String? userCountry,
  }) async {
    final response = await BackendService.getPosts(
      feedType: feedType,
      limit: limit,
      cursor: lastCursors,
      mediaType: mediaType,
      lat: latitude,
      lng: longitude,
      city: userCity,
      country: userCountry,
    );

    if (!response.success) throw response.error ?? 'Failed to fetch feed';

    final data = response.data ?? [];
    final posts = data
        .map((json) => Post.fromJson(json as Map<String, dynamic>))
        .toList();

    return PaginatedResponse<Post>(
      data: posts,
      hasMore: response.pagination?.hasMore ?? false,
      cursor: response.pagination?.cursor != null 
          ? {'id': response.pagination!.cursor} 
          : null,
    );
  }

  Future<PaginatedResponse<Post>> getFilteredPostsPaginated({
    String? authorId,
    String? category,
    String? city,
    String? country,
    int limit = 15,
    Map<String, dynamic>? lastCursors,
  }) async {
    final response = await BackendService.getFilteredPosts(
      authorId: authorId,
      category: category,
      city: city,
      country: country,
      limit: limit,
      cursor: lastCursors,
    );

    if (!response.success) throw response.error ?? 'Failed to fetch filtered feed';

    final data = response.data ?? [];
    final posts = data
        .map((json) => Post.fromJson(json as Map<String, dynamic>))
        .toList();

    return PaginatedResponse<Post>(
      data: posts,
      hasMore: response.pagination?.hasMore ?? false,
      cursor: response.pagination?.cursor != null 
          ? {'id': response.pagination!.cursor} 
          : null,
    );
  }

  Future<PaginatedResponse<Post>> getExplorePosts({int limit = 30}) async {
    final pos = LocationService.currentPosition;
    final response = await BackendService.getExplore(
      lat: pos?.latitude,
      lng: pos?.longitude,
      limit: limit,
    );

    if (!response.success) throw response.error ?? 'Failed to fetch explore';

    final data = response.data ?? [];
    final posts = data
        .map((json) => Post.fromJson(json as Map<String, dynamic>))
        .toList();

    return PaginatedResponse<Post>(
      data: posts,
      hasMore: response.pagination?.hasMore ?? false,
    );
  }

  // ─────────────────────────────────────────────
  // Posts by Author (Stream)
  // ─────────────────────────────────────────────
  Stream<List<Post>> postsByAuthor(String authorId) {
    return _postsByAuthorInternal(authorId).asBroadcastStream();
  }

  Stream<List<Post>> _postsByAuthorInternal(String authorId) async* {
    final response = await BackendService.getFilteredPosts(authorId: authorId);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      yield posts;
    }
  }

  // ─────────────────────────────────────────────
  // Create Event
  // ─────────────────────────────────────────────
  Future<Post> createEvent({
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
    final response = await BackendService.createPost({
      'text': description,
      'title': title,
      'category': 'Events',
      'city': city,
      'country': country,
      'mediaUrl': mediaUrl,
      'mediaType': 'image',
      'location': (latitude != null && longitude != null)
          ? {'lat': latitude, 'lng': longitude, 'name': city}
          : null,
      'isEvent': true,
      'eventStartDate': eventStartDate.toIso8601String(),
      'eventEndDate': eventEndDate.toIso8601String(),
      'eventLocation': location,
      'isFree': isFree,
      'eventType': eventType,
      'tags': ['Events'],
    });

    if (!response.success || response.data == null)
      throw response.error ?? 'Failed to create event';
    return Post.fromJson(response.data!);
  }

  // ─────────────────────────────────────────────
  // Standard Streams and Helpers
  // ─────────────────────────────────────────────
  Stream<List<Post>> postsByScope(String scope) {
    return _postsByScopeInternal(scope).asBroadcastStream();
  }

  Stream<List<Post>> _postsByScopeInternal(String scope) async* {
    final response = await BackendService.getFilteredPosts(category: scope);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data
          .map((json) => Post.fromJson(json as Map<String, dynamic>))
          .toList();
      yield posts;
    }
  }

  Stream<int> eventAttendeesCountStream(String eventId) {
    return _eventAttendeesCountStreamInternal(eventId).asBroadcastStream();
  }

  Stream<int> _eventAttendeesCountStreamInternal(String eventId) async* {
    final response = await BackendService.getPost(eventId);
    if (response.success) {
      yield response.data!['attendeeCount'] as int? ?? 0;
    }
  }

  Future<void> toggleEventAttendance(String eventId, String userId) async {
    final response = await BackendService.toggleEventJoin(eventId);
    if (!response.success) throw response.error ?? 'Action failed';
  }

  Stream<bool> isAttendingEventStream(String eventId, String userId) {
    return _isAttendingEventStreamInternal(eventId, userId).asBroadcastStream();
  }

  Stream<bool> _isAttendingEventStreamInternal(
    String eventId,
    String userId,
  ) async* {
    final response = await BackendService.checkEventAttendance(eventId);
    if (response.success) {
      yield response.data ?? false;
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getPost(String postId) async {
    return await BackendService.getPost(postId);
  }
}
