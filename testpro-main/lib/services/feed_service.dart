import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post.dart';
import '../repositories/feed_repository.dart';

/// Facade for [FeedRepository].
/// Provides static access to feed-related operations.
class FeedService {
  static FeedRepository _repository = FeedRepository();
  
  static FeedRepository get repository => _repository;
  
  static set repository(FeedRepository repo) => _repository = repo;

  // Recommendation Weights (Proxied)
  static const double weightWatchTime = FeedRepository.weightWatchTime;
  static const double weightLike = FeedRepository.weightLike;
  static const double weightComment = FeedRepository.weightComment;
  static const double weightShare = FeedRepository.weightShare;
  static const double weightSkipPenalty = FeedRepository.weightSkipPenalty;

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
    return _repository.logUserActivity(
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

  static Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) {
    return _repository.getRecommendedFeed(
      userId: userId,
      sessionId: sessionId,
      lastDocument: lastDocument,
      limit: limit,
    );
  }
}
