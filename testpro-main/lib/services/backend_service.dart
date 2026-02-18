import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'media_upload_service.dart';

/// Facade for Backend functionality.
/// Uses a singleton [BackendClient] to perform actual requests.
/// This allows for dependency injection and testing by swapping the underlying client.
class BackendService {
  static BackendClient _instance = BackendClient();
  
  static BackendClient get instance => _instance;
  
  @visibleForTesting
  static set instance(BackendClient v) {
    _instance = v;
  }

  // --- Static Proxies ---

  static Future<bool> toggleLike(String postId) => _instance.toggleLike(postId);

  static Future<bool> addComment(String postId, String text) => _instance.addComment(postId, text);

  static Future<bool> toggleFollow(String targetUserId) => _instance.toggleFollow(targetUserId);

  static Future<bool> toggleEventJoin(String eventId) => _instance.toggleEventJoin(eventId);
}

/// The actual implementation of backend calls.
/// Can be instantiated with a mock [http.Client] for testing.
class BackendClient {
  final http.Client _client;
  final String _baseUrl;

  BackendClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? MediaUploadService.baseUrl;

  @visibleForTesting
  Future<String?> getIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return await user.getIdToken();
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Like or unlike a post via custom backend
  Future<bool> toggleLike(String postId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/interactions/like'),
        headers: await _getHeaders(),
        body: jsonEncode({'postId': postId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error toggling like: $e');
      return false;
    }
  }

  /// Add a comment via custom backend
  Future<bool> addComment(String postId, String text) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/interactions/comment'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'postId': postId,
          'text': text,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return false;
    }
  }

  /// Follow or unfollow a user via custom backend
  Future<bool> toggleFollow(String targetUserId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/interactions/follow'),
        headers: await _getHeaders(),
        body: jsonEncode({'targetUserId': targetUserId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error toggling follow: $e');
      return false;
    }
  }

  /// Join or leave an event via custom backend
  Future<bool> toggleEventJoin(String eventId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/api/interactions/event/join'),
        headers: await _getHeaders(),
        body: jsonEncode({'eventId': eventId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error toggling event join: $e');
      return false;
    }
  }
}
