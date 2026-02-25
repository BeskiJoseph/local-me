import '../models/comment.dart';
import 'backend_service.dart';

class CommentService {
  /// One-shot stream: fetches comments once and completes.
  /// The previous 5s polling was the single worst contributor to the
  /// request storm — every open comment section fired a call every 5s.
  /// Use pull-to-refresh or re-subscribe to get fresh comments.
  static Stream<List<Comment>> commentsStream(String postId) async* {
    final response = await BackendService.getComments(postId);
    if (response.success && response.data != null) {
      yield response.data!.map<Comment>((json) => Comment.fromJson(json)).toList();
    } else {
      yield [];
    }
  }

  /// Adds a comment to a post.
  /// 
  /// Note: authorId, authorName, and authorProfileImage are handled server-side.
  static Future<void> addComment({
    required String postId,
    required String text,
  }) async {
    final response = await BackendService.addComment(postId, text);
    if (!response.success) throw response.error ?? "Failed to add comment via backend";
  }
  
  /// Future version for one-time comment fetching
  static Future<List<Comment>> getComments(String postId) async {
    final response = await BackendService.getComments(postId);
    if (response.success && response.data != null) {
      return response.data!.map<Comment>((json) => Comment.fromJson(json)).toList();
    }
    return [];
  }
}
