import '../models/post.dart';
import '../services/backend_service.dart';

/// Repository for handling Feed Recommendation and User Activity Logging.
class FeedRepository {
  FeedRepository();

  Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    String? afterId,
    int limit = 10,
  }) async {
    final response = await BackendService.getFeed(
      cursor: afterId,
      limit: limit,
      type: 'personalized',
    );
    
    if (!response.success) throw response.error ?? "Failed to fetch recommendations";
    
    final posts = (response.data as List).map((json) => Post.fromJson(json)).toList();
    return posts;
  }
}
