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
  static Future<ApiResponse<List<dynamic>>> getPosts({
    String? authorId,
    String? category,
    String? city,
    String? country,
    double? lat,
    double? lng,
    String? feedType,
    int limit = 20,
    String? afterId,
    double? lastDistance,
    String? lastPostId,
    String? watchedIds,
  }) => _instance.getPosts(
    authorId: authorId,
    category: category,
    city: city,
    country: country,
    lat: lat,
    lng: lng,
    feedType: feedType,
    limit: limit,
    afterId: afterId,
    lastDistance: lastDistance,
    lastPostId: lastPostId,
    watchedIds: watchedIds,
  );
  static Future<ApiResponse<List<dynamic>>> getComments(String postId, {String? afterId, int limit = 20, String sort = 'newest'}) => 
      _instance.getComments(postId, afterId: afterId, limit: limit, sort: sort);
  static Future<ApiResponse<List<dynamic>>> getReplies(String commentId, {String? afterId, int limit = 10}) => 
      _instance.getReplies(commentId, afterId: afterId, limit: limit);
  static Future<ApiResponse<bool>> toggleCommentLike(String commentId) => _instance.toggleCommentLike(commentId);
  static Future<ApiResponse<Map<String, dynamic>>> addComment(String postId, String text, {String? parentId}) => 
      _instance.addComment(postId, text, parentId: parentId);
  static Future<ApiResponse<List<dynamic>>> search({required String query, String type = 'posts', int limit = 20}) => 
      _instance.search(query: query, type: type, limit: limit);
  static Future<ApiResponse<List<dynamic>>> getNotifications() => _instance.getNotifications();
  static Future<ApiResponse<bool>> markNotificationAsRead(String id) => _instance.markNotificationAsRead(id);
  static Future<ApiResponse<Map<String, dynamic>>> checkLikeState(String postId) => _instance.checkLikeState(postId);
  static Future<ApiResponse<bool>> checkFollowState(String targetUserId) => _instance.checkFollowState(targetUserId);
  static Future<ApiResponse<bool>> checkUsername(String username) => _instance.checkUsername(username);
  static Future<ApiResponse<bool>> checkEventAttendance(String eventId) => _instance.checkEventAttendance(eventId);
  static Future<ApiResponse<List<String>>> getMyEventIds() => _instance.getMyEventIds();
  static Future<ApiResponse<bool>> trackPostView(String postId) => _instance.trackPostView(postId);
  static Future<ApiResponse<Map<String, dynamic>>> getPostInsights(String postId) => _instance.getPostInsights(postId);
  static Future<ApiResponse<bool>> muteUser(String userId) => _instance.muteUser(userId);
  static Future<ApiResponse<bool>> unmuteUser(String userId) => _instance.unmuteUser(userId);
  static Future<ApiResponse<bool>> reportPost(String postId, String reason) => _instance.reportPost(postId, reason);
  static Future<ApiResponse<List<dynamic>>> getNewPostsSince({
    required double lat,
    required double lng,
    required int sinceTimestamp,
    double? maxDistance,
  }) => _instance.getNewPostsSince(
    lat: lat,
    lng: lng,
    sinceTimestamp: sinceTimestamp,
    maxDistance: maxDistance,
  );
  
  // --- Session Management ---
  static Future<void> syncCustomTokens() => BackendClient.syncCustomTokens();
  static void clearSession() => BackendClient.clearSession();
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

  static String? _customAccessToken;
  static String? _customRefreshToken;
  static Future<void>? _syncFuture;
  static bool _customSessionUnsupported = false;

  /// Exchanges a Firebase ID Token for a custom Access/Refresh Token pair.
  /// Deduplicated to prevent concurrent sync calls.
  static Future<void> syncCustomTokens() async {
    if (_customSessionUnsupported) return;

    // If a sync is already in progress, return the existing future
    if (_syncFuture != null) return _syncFuture;

    _syncFuture = _performSync();
    try {
      await _syncFuture;
    } finally {
      // Clear the future once done (success or fail) to allow future syncs if needed
      _syncFuture = null;
    }
  }

  static Future<void> _performSync() async {
    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        debugPrint('⚠️ Sync skipped: User not authenticated in Firebase');
        return;
      }

      final response = await BackendService.instance._sendRequest((token) async {
         return await http.post(
           Uri.parse('${MediaUploadService.baseUrl}/api/auth/token'),
           headers: {'Content-Type': 'application/json'},
           body: jsonEncode({'idToken': token}),
         );
      }, skipCustomCheck: true);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>?;
        _customAccessToken = data?['accessToken'] as String?;
        _customRefreshToken = data?['refreshToken'] as String?;
        if (_customAccessToken != null && _customRefreshToken != null) {
          debugPrint('🛡️ Custom session tokens established');
        }
      } else {
        Map<String, dynamic>? body;
        try {
          body = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        final rawError = body?['error'];
        final errorMessage = rawError is String
            ? rawError
            : (rawError is Map<String, dynamic> ? (rawError['message']?.toString() ?? 'unknown') : 'unknown');

        if (response.statusCode == 500 && errorMessage.toLowerCase().contains('configuration')) {
          _customSessionUnsupported = true;
          _customAccessToken = null;
          _customRefreshToken = null;
          debugPrint('⚠️ Custom JWT backend not configured; using Firebase auth only.');
          return;
        }

        debugPrint('❌ Custom session sync failed: ${response.statusCode} - ${response.body}');
        // If the server explicitly rejects the token with 401/403, 
        // we clear local state to prevent further loops
        if (response.statusCode == 401 || response.statusCode == 403) {
          _customAccessToken = null;
          _customRefreshToken = null;
        }
      }
    } catch (e) {
      debugPrint('🚨 Error during token synchronization: $e');
    }
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function(String token) requestFn, {
    bool retried = false,
    bool skipCustomCheck = false,
  }) async {
    // 1. Use Custom Token if available
    if (!skipCustomCheck && _customAccessToken != null) {
      final response = await requestFn(_customAccessToken!).timeout(const Duration(seconds: 30));
      if (response.statusCode == 401 && !retried) {
        // Attempt Custom Refresh
        if (_customRefreshToken != null) {
           final refreshed = await _refreshCustomToken();
           if (refreshed) return await _sendRequest(requestFn, retried: true);
        }
        // If refresh failed or was null, clear tokens and let fallback happen
        _customAccessToken = null;
        _customRefreshToken = null;
      } else {
        return response;
      }
    }

    // 2. Fallback to Firebase Token Flow (Clean Architecture)
    final firebaseToken = await getIdToken();
    if (firebaseToken == null) throw StateError('User not authenticated');

    final response = await requestFn(firebaseToken).timeout(const Duration(seconds: 30));
    
    // We NO LONGER call syncCustomTokens() here to prevent side-effect loops.
    // Sync should be orchestrated by the AuthState listener or an explicit login call.

    if (response.statusCode == 401 && !retried) {
      final newToken = await AuthService.getIdToken(forceRefresh: true);
      if (newToken != null) {
        return await _sendRequest(requestFn, retried: true);
      }
    }
    return response;
  }

  static void clearSession() {
    _customAccessToken = null;
    _customRefreshToken = null;
    _syncFuture = null;
    _customSessionUnsupported = false;
    debugPrint('🛡️ Custom session tokens cleared');
  }

  Future<bool> _refreshCustomToken() async {
    if (_customRefreshToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse('${MediaUploadService.baseUrl}/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _customRefreshToken}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        _customAccessToken = body['data']['accessToken'];
        _customRefreshToken = body['data']['refreshToken'];
        debugPrint('🛡️ Custom session rotated successfully');
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
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
    // Redirect legacy /feed calls to /posts for backward compatibility
    return getPosts(afterId: cursor, limit: limit);
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

  Future<ApiResponse<Map<String, dynamic>>> addComment(String postId, String text, {String? parentId}) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/comment'),
        headers: await _getHeaders(token),
        body: jsonEncode({
          'postId': postId,
          'text': text,
          if (parentId != null) 'parentId': parentId,
        }),
      ));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> toggleCommentLike(String commentId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/interactions/comments/$commentId/like'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
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

  Future<ApiResponse<List<dynamic>>> getPosts({
    String? authorId,
    String? category,
    String? city,
    String? country,
    double? lat,
    double? lng,
    String? feedType, // 'local' or 'global'
    int limit = 20,
    String? afterId,
    double? lastDistance,
    String? lastPostId,
    String? watchedIds,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts').replace(queryParameters: {
        if (authorId != null) 'authorId': authorId,
        if (category != null) 'category': category,
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
        if (feedType != null) 'feedType': feedType,
        if (afterId != null) 'afterId': afterId,
        if (lastDistance != null) 'lastDistance': lastDistance.toString(),
        if (lastPostId != null) 'lastPostId': lastPostId,
        if (watchedIds != null) 'watchedIds': watchedIds,
        'limit': limit.toString(),
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getComments(String postId, {String? afterId, int limit = 20, String sort = 'newest'}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/comments/$postId').replace(queryParameters: {
        'limit': limit.toString(),
        if (afterId != null) 'afterId': afterId,
        'sort': sort,
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getReplies(String commentId, {String? afterId, int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/comments/$commentId/replies').replace(queryParameters: {
        'limit': limit.toString(),
        if (afterId != null) 'afterId': afterId,
      });
      final resp = await _sendRequest((token) async => await _client.get(uri, headers: await _getHeaders(token)));
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

  Future<ApiResponse<List<String>>> getMyEventIds() async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/interactions/events/my-events'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) {
        final ids = d['eventIds'] as List<dynamic>;
        return ids.map((e) => e.toString()).toList();
      });
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> trackPostView(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/posts/$postId/view'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<Map<String, dynamic>>> getPostInsights(String postId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.get(
        Uri.parse('$_baseUrl/api/posts/$postId/insights'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> muteUser(String userId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/profiles/mute/$userId'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> unmuteUser(String userId) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/profiles/unmute/$userId'),
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<bool>> reportPost(String postId, String reason) async {
    try {
      final resp = await _sendRequest((token) async => await _client.post(
        Uri.parse('$_baseUrl/api/posts/$postId/report'),
        headers: await _getHeaders(token),
        body: jsonEncode({'reason': reason}),
      ));
      return _processResponse(resp, (_) => true);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }

  Future<ApiResponse<List<dynamic>>> getNewPostsSince({
    required double lat,
    required double lng,
    required int sinceTimestamp,
    double? maxDistance,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts/new-since').replace(queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'sinceTimestamp': sinceTimestamp.toString(),
        if (maxDistance != null) 'maxDistance': maxDistance.toString(),
      });
      final resp = await _sendRequest((token) async => await _client.get(
        uri,
        headers: await _getHeaders(token),
      ));
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) { return ApiResponse(success: false, error: e.toString()); }
  }
}

