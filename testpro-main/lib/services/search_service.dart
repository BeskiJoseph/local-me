import 'backend_service.dart';

class SearchService {
  // Search users by username via backend
  static Future<List<dynamic>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];

    final response = await BackendService.search(
      query: query.trim(),
      type: 'users',
      limit: 20,
    );
    return response.data ?? [];
  }

  // Search posts by text via backend
  static Future<List<dynamic>> searchPosts(String query) async {
    if (query.trim().isEmpty) return [];

    final response = await BackendService.search(
      query: query.trim(),
      type: 'posts',
      limit: 20,
    );
    return response.data ?? [];
  }
}
