import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'media_upload_service.dart';
import 'auth_service.dart';
import '../models/api_response.dart';

/// Facade for Backend functionality.
/// Uses a singleton [BackendClient] to perform actual requests.
class BackendService {
  static BackendClient _instance = BackendClient();
  
  static BackendClient get instance => _instance;
  
  @visibleForTesting
  static set instance(BackendClient v) {
    _instance = v;
  }

  // --- Static Proxies ---
  static Future<ApiResponse<bool>> toggleLike(String postId) => _instance.toggleLike(postId);
  static Future<ApiResponse<String>> addComment(String postId, String text) => _instance.addComment(postId, text);
  static Future<ApiResponse<bool>> toggleFollow(String targetUserId) => _instance.toggleFollow(targetUserId);
  static Future<ApiResponse<bool>> toggleEventJoin(String eventId) => _instance.toggleEventJoin(eventId);
  static Future<ApiResponse<String>> createPost(Map<String, dynamic> data) => _instance.createPost(data);
  static Future<ApiResponse<Map<String, dynamic>>> getPost(String postId) => _instance.getPost(postId);
  static Future<ApiResponse<List<dynamic>>> getFeed({String? cursor, int limit = 10, String type = 'discovery'}) => 
      _instance.getFeed(cursor: cursor, limit: limit, type: type);
  static Future<ApiResponse<Map<String, dynamic>>> getProfile(String uid) => _instance.getProfile(uid);
  static Future<ApiResponse<bool>> updateProfile(Map<String, dynamic> data) => _instance.updateProfile(data);
  static Future<ApiResponse<bool>> deletePost(String postId) => _instance.deletePost(postId);
  static Future<ApiResponse<List<dynamic>>> getMessages(String eventId) => _instance.getMessages(eventId);
  static Future<ApiResponse<bool>> sendChatMessage(String eventId, String text) => _instance.sendChatMessage(eventId, text);
  static Future<ApiResponse<List<dynamic>>> getPosts({String? authorId, String? category, String? city, int limit = 20, String? afterId}) => 
      _instance.getPosts(authorId: authorId, category: category, city: city, limit: limit, afterId: afterId);
  static Future<ApiResponse<List<dynamic>>> getComments(String postId) => _instance.getComments(postId);
  static Future<ApiResponse<List<dynamic>>> search({required String query, String type = 'posts', int limit = 20}) => 
      _instance.search(query: query, type: type, limit: limit);
  static Future<ApiResponse<List<dynamic>>> getNotifications() => _instance.getNotifications();
  static Future<ApiResponse<bool>> markNotificationAsRead(String id) => _instance.markNotificationAsRead(id);
  static Future<ApiResponse<Map<String, dynamic>>> checkLikeState(String postId) => _instance.checkLikeState(postId);
  static Future<ApiResponse<bool>> checkFollowState(String targetUserId) => _instance.checkFollowState(targetUserId);
  static Future<ApiResponse<bool>> checkUsername(String username) => _instance.checkUsername(username);
  static Future<ApiResponse<bool>> checkEventAttendance(String eventId) => _instance.checkEventAttendance(eventId);
}


class BackendClient {
  final http.Client _client;
  final String _baseUrl;

  BackendClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? MediaUploadService.baseUrl;

  Future<String?> getIdToken() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final token = await AuthService.getIdToken();
      if (token != null) return token;
      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<Map<String, String>> _getHeaders([String? token]) async {
    final effectiveToken = token ?? await getIdToken();
    return {
      'Content-Type': 'application/json',
      if (effectiveToken != null) 'Authorization': 'Bearer $effectiveToken',
    };
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function(String token) requestFn, {
    bool retried = false,
  }) async {
    final token = await getIdToken();
    if (token == null) throw StateError('User not authenticated');

    final response = await requestFn(token);
    if (response.statusCode == 401 && !retried) {
      final newToken = await AuthService.getIdToken(forceRefresh: true);
      if (newToken != null) {
        return await _sendRequest(requestFn, retried: true);
      }
    }
    return response;
  }

  ApiResponse<T> _processResponse<T>(http.Response response, T Function(dynamic data) mapper) {
    try {
      final Map<String, dynamic> body = jsonDecode(response.body);
      return ApiResponse<T>.fromJson(body, mapper);
    } catch (e) {
      debugPrint('API Error: ${response.statusCode} - ${response.body}');
      return ApiResponse<T>(
        success: false,
        error: 'Network or Parsing Error: $e',
        errorCode: 'NETWORK_ERROR',
      );
    }
  }

  // --- Implementations ---

  Future<ApiResponse<String>> createPost(Map<String, dynamic> data) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/posts'),
        headers: await _getHeaders(token),
        body: jsonEncode(data),
      ));
      return _processResponse(resp, (d) => d['id'] as String);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<Map<String, dynamic>>> getPost(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/posts/$postId'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getFeed({String? cursor, int limit = 10, String type = 'discovery'}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts/feed').replace(queryParameters: {
        if (cursor != null) 'cursor': cursor,
        'limit': limit.toString(),
        'type': type,
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<Map<String, dynamic>>> getProfile(String uid) async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/profiles/$uid'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> updateProfile(Map<String, dynamic> data) async {
    try {
      final resp = await _sendRequest((token) async => await _client.patch(
        Uri.parse('$_baseUrl/api/profiles/me'),
        headers: await _getHeaders(token),
        body: jsonEncode(data),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> toggleLike(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/like'),
        headers: await _getHeaders(token),
        body: jsonEncode({'postId': postId}),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<String>> addComment(String postId, String text) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/comment'),
        headers: await _getHeaders(token),
        body: jsonEncode({'postId': postId, 'text': text}),
      ));
      return _processResponse(resp, (d) => d['commentId'] as String);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> toggleFollow(String targetUserId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/follow'),
        headers: await _getHeaders(token),
        body: jsonEncode({'targetUserId': targetUserId}),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> toggleEventJoin(String eventId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/event/join'),
        headers: await _getHeaders(token),
        body: jsonEncode({'eventId': eventId}),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> deletePost(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.delete(
        Uri.parse('$_baseUrl/api/posts/$postId'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getMessages(String eventId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/posts/$eventId/messages'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> sendChatMessage(String eventId, String text) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/posts/$eventId/messages'),
        headers: await _getHeaders(token),
        body: jsonEncode({'text': text}),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getPosts({String? authorId, String? category, String? city, int limit = 20, String? afterId}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts').replace(queryParameters: {
        if (authorId != null) 'authorId': authorId,
        if (category != null) 'category': category,
        if (city != null) 'city': city,
        if (afterId != null) 'afterId': afterId,
        'limit': limit.toString(),
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getComments(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/interactions/comments/$postId'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> search({required String query, String type = 'posts', int limit = 20}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search').replace(queryParameters: {
        'q': query,
        'type': type,
        'limit': limit.toString(),
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getNotifications() async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/notifications'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> markNotificationAsRead(String id) async {
    try {
      final resp = await _sendRequest((token) async => await _client.patch(
        Uri.parse('$_baseUrl/api/notifications/$id/read'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<Map<String, dynamic>>> checkLikeState(String postId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/likes/check').replace(queryParameters: {'postId': postId});
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<Map<String, dynamic>>> getLikesBatch(List<String> postIds) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/likes/batch'),
        headers: await _getHeaders(token),
        body: jsonEncode({'postIds': postIds}),
      ));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> checkFollowState(String targetUserId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/follows/check').replace(queryParameters: {'targetUserId': targetUserId});
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d['followed'] == true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> checkUsername(String username) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/profiles/check-username').replace(queryParameters: {'username': username});
      final resp = await _client.get(uri, headers: {'Content-Type': 'application/json'});
      return _processResponse(resp, (d) => d['available'] == true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> checkEventAttendance(String eventId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/events/check').replace(queryParameters: {'eventId': eventId});
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d['attending'] == true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }
}

