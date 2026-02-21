import '../models/post.dart';
import '../repositories/feed_repository.dart';

/// Facade for [FeedRepository].
class FeedService {
  static FeedRepository _repository = FeedRepository();
  
  static FeedRepository get repository => _repository;
  
  static set repository(FeedRepository repo) => _repository = repo;

  static Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    String? afterId,
    int limit = 10,
  }) {
    return _repository.getRecommendedFeed(
      userId: userId,
      sessionId: sessionId,
      afterId: afterId,
      limit: limit,
    );
  }
}
