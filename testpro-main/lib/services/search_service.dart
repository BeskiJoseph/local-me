import 'backend_service.dart';

class SearchService {
  /// Search users and posts in a single API call
  static Future<Map<String, List<dynamic>>> searchAll(String query) async {
    if (query.trim().isEmpty) return {'users': [], 'posts': []};

    final response = await BackendService.searchAll(
      query: query.trim(),
      limit: 20,
    );

    if (response.success && response.data != null) {
      return {
        'users': (response.data!['users'] as List<dynamic>?) ?? [],
        'posts': (response.data!['posts'] as List<dynamic>?) ?? [],
      };
    }

    return {'users': [], 'posts': []};
  }

  // Legacy methods for backward compatibility
  static Future<List<dynamic>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await BackendService.search(query: query.trim(), type: 'users', limit: 20);
    return response.data ?? [];
  }

  static Future<List<dynamic>> searchPosts(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await BackendService.search(query: query.trim(), type: 'posts', limit: 20);
    return response.data ?? [];
  }
}
