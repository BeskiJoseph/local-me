import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../repositories/post_repository.dart';

/// Facade for [PostRepository].
/// Provides static access to post-related operations while allowing
/// the underlying repository to be swapped for testing.
class PostService {
  static PostRepository _repository = PostRepository();

  static PostRepository get repository => _repository;

  static set repository(PostRepository repo) {
    _repository = repo;
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
    return _repository.createPost(
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
    return _repository.deletePost(postId);
  }

  static Stream<List<Post>> postsByScope(String scope) {
    return _repository.postsByScope(scope);
  }

  static Future<List<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) {
    return _repository.getPostsPaginated(
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
    return _repository.postsForFeed(
      feedType: feedType,
      userCity: userCity,
      userCountry: userCountry,
    );
  }

  static Stream<List<Post>> postsByAuthor(String authorId) {
    return _repository.postsByAuthor(authorId);
  }

  static Stream<QuerySnapshot> getPostsStream() {
    return _repository.getPostsStream();
  }

  // --- Event Related Methods ---

  static Stream<int> eventAttendeesCountStream(String eventId) {
    return _repository.eventAttendeesCountStream(eventId);
  }

  static Stream<bool> isAttendingEventStream(String eventId, String userId) {
    return _repository.isAttendingEventStream(eventId, userId);
  }

  static Future<void> toggleEventAttendance(String eventId, String userId) {
    return _repository.toggleEventAttendance(eventId, userId);
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
    return _repository.createEvent(
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
}
