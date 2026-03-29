import '../../services/post_service.dart';
import '../models/post.dart' as new_model;
import '../models/feed_type.dart';
import '../../models/post.dart' as old_model;
import '../../models/paginated_response.dart';

/// Service responsible for fetching posts from the backend and 
/// adapting them to the new core_feed domain models.
class FeedService {
  
  /// Fetches a page of posts for a specific feed type/stage.
  Future<FeedBatch> fetchFeedBatch({
    required FeedType type,
    required FeedStage stage,
    String? authorId, 
    String? mediaType, // ✅ NEW: Support for 'video' filter (Reels)
    dynamic cursor,
    double? latitude,
    double? longitude,
    String? city,
    String? country,
  }) async {
    
    // 🥇 Phase 7.1: Handling Profile Mode
    if (type == FeedType.profile) {
      final response = await PostService.getFilteredPostsPaginated(
        authorId: authorId,
        lastCursors: cursor as Map<String, dynamic>?,
        limit: 15,
      );
      return _mapResponse(response);
    }

    // Phase 6 & 7: Handling Feed/Reels Mode
    String legacyFeedType = (type == FeedType.global) ? 'global' : 'hybrid';
    double? lat = latitude;
    double? lng = longitude;
    String? cityParam = city;

    // Discovery Logic (Only for Home Feed)
    if (type == FeedType.home) {
      switch (stage) {
        case FeedStage.ultraLocal:
          lat = latitude;
          lng = longitude;
          cityParam = null;
          break;
        case FeedStage.city:
          lat = null;
          lng = null;
          cityParam = city;
          break;
        case FeedStage.global:
          legacyFeedType = 'global';
          lat = null;
          lng = null;
          cityParam = null;
          break;
        default:
          break;
      }
    }

    final response = await PostService.getPostsPaginated(
      feedType: legacyFeedType,
      lastCursors: cursor as Map<String, dynamic>?,
      mediaType: mediaType, // ✅ Pass mediaType (e.g., 'video' for Reels)
      latitude: lat,
      longitude: lng,
      userCity: cityParam,
      userCountry: country,
    );

    return _mapResponse(response);
  }

  /// Helper to map older PaginatedResponse<old_model.Post> to new FeedBatch
  FeedBatch _mapResponse(PaginatedResponse<old_model.Post> response) {
    final List<new_model.Post> newPosts = response.data.map((oldPost) {
      return new_model.Post(
        id: oldPost.id,
        authorId: oldPost.authorId,
        authorName: oldPost.authorName,
        authorProfileImage: oldPost.authorProfileImage,
        title: oldPost.title,
        body: oldPost.body,
        mediaUrl: oldPost.mediaUrl,
        mediaType: oldPost.mediaType,
        likeCount: oldPost.likeCount,
        commentCount: oldPost.commentCount,
        viewCount: oldPost.viewCount,
        createdAt: oldPost.createdAt,
        latitude: oldPost.latitude,
        longitude: oldPost.longitude,
        isLiked: oldPost.isLiked,
        isFollowing: oldPost.isFollowing,
      );
    }).toList();

    return FeedBatch(
      posts: newPosts,
      nextCursor: response.cursor,
      hasMore: response.hasMore,
    );
  }
}

class FeedBatch {
  final List<new_model.Post> posts;
  final dynamic nextCursor;
  final bool hasMore;

  FeedBatch({
    required this.posts,
    this.nextCursor,
    required this.hasMore,
  });
}
