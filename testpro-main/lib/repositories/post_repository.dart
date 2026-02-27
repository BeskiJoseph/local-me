import '../models/post.dart';
import '../models/paginated_response.dart';
import '../services/backend_service.dart';
import '../services/location_service.dart';

/// Repository for handling Post and Event data operations.
class PostRepository {
  PostRepository();

  /// Creates a post via REST.
  Future<String> createPost({
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
      'location': (latitude != null && longitude != null) ? {
        'lat': latitude,
        'lng': longitude,
        'name': city ?? 'Unknown'
      } : null,
      'tags': [category],
    });

    if (!response.success) throw response.error ?? "Failed to create post";
    return response.data!;
  }

  Future<void> deletePost(String postId) async {
    final response = await BackendService.deletePost(postId);
    if (!response.success) throw response.error ?? "Failed to delete post";
  }

  Future<PaginatedResponse<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    String? afterId,
    int limit = 10,
  }) async {
    final pos = LocationService.currentPosition;
    final response = await BackendService.getPosts(
      afterId: afterId,
      limit: limit,
      lat: pos?.latitude,
      lng: pos?.longitude,
      country: userCountry,
      feedType: feedType, // Pass 'local' or 'global'
    );
    
    if (!response.success) throw response.error ?? "Failed to fetch feed";
    
    final data = response.data ?? [];
    final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
    
    return PaginatedResponse<Post>(
      data: posts,
      nextCursor: response.pagination?.cursor,
      hasMore: response.pagination?.hasMore ?? false,
    );
  }

  Stream<List<Post>> postsByAuthor(String authorId) async* {
    final response = await BackendService.getPosts(authorId: authorId);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      yield posts;
    }
  }

  Stream<int> eventAttendeesCountStream(String eventId) async* {
    final response = await BackendService.getPost(eventId);
    if (response.success) {
      yield response.data!['attendeeCount'] as int? ?? 0;
    }
  }

  Future<void> toggleEventAttendance(String eventId, String userId) async {
    final response = await BackendService.toggleEventJoin(eventId);
    if (!response.success) throw response.error ?? "Action failed";
  }

  Future<String> createEvent({
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
      'location': (latitude != null && longitude != null) ? {
        'lat': latitude,
        'lng': longitude,
        'name': city,
      } : null,
      'isEvent': true,
      'eventStartDate': eventStartDate.toIso8601String(),
      'eventEndDate': eventEndDate.toIso8601String(),
      'eventLocation': location,
      'isFree': isFree,
      'eventType': eventType,
      'tags': ['Events'],
    });

    if (!response.success) throw response.error ?? "Failed to create event";
    return response.data!;
  }

  Stream<List<Post>> postsByScope(String scope) async* {
    final response = await BackendService.getPosts(category: scope);
    if (response.success) {
      final data = response.data ?? [];
      final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      yield posts;
    }
  }

  Stream<List<Post>> postsForFeed({
    required String feedType,
    String? userCity,
    String? userCountry,
  }) async* {
    final pos = LocationService.currentPosition;
    final response = await BackendService.getPosts(
      afterId: feedType == 'global' ? null : null, // cursor handling differs?
      limit: 20,
      lat: pos?.latitude,
      lng: pos?.longitude,
      country: userCountry,
    );
    if (response.success) {
      final data = response.data ?? [];
      final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
      yield posts;
    }
  }
  Stream<bool> isAttendingEventStream(String eventId, String userId) async* {
    final response = await BackendService.checkEventAttendance(eventId);
    if (response.success) {
      yield response.data ?? false;
    }
  }
}

