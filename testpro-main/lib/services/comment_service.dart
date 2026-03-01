import '../models/comment.dart';
import 'backend_service.dart';

class CommentService {
  /// Fetches top-level comments for a post with cursor-based pagination.
  static Future<List<Comment>> getComments(String postId, {String? afterId, int limit = 20, String sort = 'newest'}) async {
    final response = await BackendService.getComments(postId, afterId: afterId, limit: limit, sort: sort);
    if (response.success && response.data != null) {
      return response.data!.map<Comment>((json) => Comment.fromJson(json)).toList();
    }
    return [];
  }

  /// Fetches replies for a specific top-level comment.
  static Future<List<Comment>> getReplies(String commentId, {String? afterId, int limit = 10}) async {
    final response = await BackendService.getReplies(commentId, afterId: afterId, limit: limit);
    if (response.success && response.data != null) {
      return response.data!.map<Comment>((json) => Comment.fromJson(json)).toList();
    }
    return [];
  }

  /// Adds a comment or reply.
  static Future<Comment> addComment({
    required String postId,
    required String text,
    String? parentId,
  }) async {
    final response = await BackendService.addComment(postId, text, parentId: parentId);
    if (response.success && response.data != null) {
      return Comment.fromJson(response.data!);
    }
    throw response.error ?? "Failed to add comment";
  }

  /// Toggles like on a comment.
  static Future<bool> toggleLike(String commentId) async {
    final response = await BackendService.toggleCommentLike(commentId);
    return response.success;
  }
}
