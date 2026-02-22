import '../models/post.dart';
import '../services/backend_service.dart';
import '../services/location_service.dart';

/// Repository for handling Feed Recommendation and User Activity Logging.
class FeedRepository {
  FeedRepository();

  Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    String? afterId,
    int limit = 10,
  }) async {
    final response = await BackendService.getPosts(
      afterId: afterId,
      limit: limit,
    );
    
    if (!response.success) throw response.error ?? "Failed to fetch recommendations";
    
    final data = response.data ?? [];
    final posts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
    return posts;
  }
}
