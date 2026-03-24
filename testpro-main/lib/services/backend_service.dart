import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:testpro/services/media_upload_service.dart';
import 'package:testpro/services/auth_service.dart';
import 'package:testpro/models/api_response.dart';
import 'package:testpro/core/auth/auth_event_stream.dart';
import 'package:testpro/core/state/feed_session.dart';

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
  static Future<ApiResponse<Map<String, dynamic>>> toggleLike(String postId) =>
      _instance.toggleLike(postId);
  static Future<ApiResponse<bool>> toggleFollow(String targetUserId) =>
      _instance.toggleFollow(targetUserId);
  static Future<ApiResponse<bool>> toggleEventJoin(String eventId) =>
      _instance.toggleEventJoin(eventId);
  static Future<ApiResponse<Map<String, dynamic>>> createPost(
    Map<String, dynamic> data,
  ) => _instance.createPost(data);
  static Future<ApiResponse<Map<String, dynamic>>> getPost(String postId) =>
      _instance.getPost(postId);
  static Future<ApiResponse<Map<String, dynamic>>> getProfile(String uid) =>
      _instance.getProfile(uid);
  static Future<ApiResponse<bool>> updateProfile(Map<String, dynamic> data) =>
      _instance.updateProfile(data);
  static Future<ApiResponse<bool>> updatePost(
    String postId,
    Map<String, dynamic> data,
  ) => _instance.updatePost(postId, data);
  static Future<ApiResponse<bool>> deletePost(String postId) =>
      _instance.deletePost(postId);
  static Future<ApiResponse<List<dynamic>>> getMessages(String eventId) =>
      _instance.getMessages(eventId);
  static Future<ApiResponse<bool>> sendEventMessage(
    String eventId,
    String text,
  ) => _instance.sendEventMessage(eventId, text);
  static Future<ApiResponse<List<dynamic>>> getPosts({
    required String feedType,
    double? lat,
    double? lng,
    String? city,
    String? country,
    int limit = 15,
    Map<String, dynamic>? cursor,
    String? mediaType,
  }) => _instance.getPosts(
    feedType: feedType,
    lat: lat,
    lng: lng,
    city: city,
    country: country,
    limit: limit,
    cursor: cursor,
    mediaType: mediaType,
  );

  static Future<ApiResponse<List<dynamic>>> getFilteredPosts({
    String? authorId,
    String? category,
    String? city,
    String? country,
    int limit = 15,
    Map<String, dynamic>? cursor,
  }) => _instance.getFilteredPosts(
    authorId: authorId,
    category: category,
    city: city,
    country: country,
    limit: limit,
    cursor: cursor,
  );

  static Future<ApiResponse<List<dynamic>>> getExplore({
    double? lat,
    double? lng,
    int limit = 30,
  }) => _instance.getExplore(lat: lat, lng: lng, limit: limit);
  static Future<ApiResponse<List<dynamic>>> getComments(
    String postId, {
    String? afterId,
    int limit = 20,
    String sort = 'newest',
  }) =>
      _instance.getComments(postId, afterId: afterId, limit: limit, sort: sort);
  static Future<ApiResponse<List<dynamic>>> getReplies(
    String commentId, {
    String? afterId,
    int limit = 10,
  }) => _instance.getReplies(commentId, afterId: afterId, limit: limit);
  static Future<ApiResponse<bool>> toggleCommentLike(String commentId) =>
      _instance.toggleCommentLike(commentId);
  static Future<ApiResponse<Map<String, dynamic>>> addComment(
    String postId,
    String text, {
    String? parentId,
  }) => _instance.addComment(postId, text, parentId: parentId);
  static Future<ApiResponse<List<dynamic>>> search({
    required String query,
    String type = 'posts',
    int limit = 20,
  }) => _instance.search(query: query, type: type, limit: limit);
  static Future<ApiResponse<Map<String, dynamic>>> searchAll({
    required String query,
    int limit = 20,
  }) => _instance.searchAll(query: query, limit: limit);
  static Future<ApiResponse<List<dynamic>>> getNotifications({String? type}) =>
      _instance.getNotifications(type: type);
  static Future<ApiResponse<bool>> markNotificationAsRead(String id) =>
      _instance.markNotificationAsRead(id);
  static Future<ApiResponse<int>> markAllNotificationsAsRead() =>
      _instance.markAllNotificationsAsRead();
  static Future<ApiResponse<Map<String, dynamic>>> checkLikeState(
    String postId,
  ) => _instance.checkLikeState(postId);
  static Future<ApiResponse<bool>> checkFollowState(String targetUserId) =>
      _instance.checkFollowState(targetUserId);
  static Future<ApiResponse<bool>> checkUsername(String username) =>
      _instance.checkUsername(username);
  static Future<ApiResponse<bool>> checkEventAttendance(String eventId) =>
      _instance.checkEventAttendance(eventId);
  static Future<ApiResponse<List<String>>> getMyEventIds() =>
      _instance.getMyEventIds();
  static Future<ApiResponse<bool>> trackPostView(String postId) =>
      _instance.trackPostView(postId);
  static Future<ApiResponse<Map<String, dynamic>>> getPostInsights(
    String postId,
  ) => _instance.getPostInsights(postId);
  static Future<ApiResponse<bool>> muteUser(String userId) =>
      _instance.muteUser(userId);
  static Future<ApiResponse<bool>> unmuteUser(String userId) =>
      _instance.unmuteUser(userId);
  static Future<ApiResponse<bool>> reportPost(String postId, String reason) =>
      _instance.reportPost(postId, reason);
  static Future<ApiResponse<bool>> savePost(String postId) =>
      _instance.savePost(postId);
  static Future<ApiResponse<bool>> unsavePost(String postId) =>
      _instance.unsavePost(postId);
  static Future<ApiResponse<bool>> hidePost(String postId) =>
      _instance.hidePost(postId);
  static Future<ApiResponse<List<dynamic>>> getChats() => _instance.getChats();
  static Future<ApiResponse<Map<String, dynamic>>> getOrCreateChat(
    String targetUserId,
  ) => _instance.getOrCreateChat(targetUserId);
  static Future<ApiResponse<Map<String, dynamic>>> sendChatMessage({
    required String chatId,
    required String text,
  }) => _instance.sendChatMessage(chatId: chatId, text: text);
  static Future<ApiResponse<bool>> markChatAsRead(String chatId) =>
      _instance.markChatAsRead(chatId);
  static Future<ApiResponse<List<dynamic>>> getNewPostsSince({
    double? lat,
    double? lng,
    String? city,
    required int sinceTimestamp,
    double? maxDistance,
    String? watchedIds,
    String? sid,
    String? mediaType,
  }) => _instance.getNewPostsSince(
    lat: lat,
    lng: lng,
    city: city,
    sinceTimestamp: sinceTimestamp,
    maxDistance: maxDistance,
    watchedIds: watchedIds,
    sid: sid,
    mediaType: mediaType,
  );

  // --- Session Management ---
  static Future<void> syncCustomTokens() => BackendClient.syncCustomTokens();
  static void clearSession() => BackendClient.clearSession();
  static Future<void> validateServer() => _instance.validateServer();

  /// Stream of authentication failures. Listen to this to trigger global logout.
  static Stream<void> get onAuthFailure =>
      BackendClient.authFailureController.stream;
}

class BackendClient {
  final http.Client _client;
  final String _baseUrl;

  BackendClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? MediaUploadService.baseUrl;

  String? get currentUserId => AuthService.currentUser?.uid;

  Future<String?> getIdToken() async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final token = await AuthService.getIdToken();
      if (token != null) return token;
      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  /// Returns the current best authentication token.
  /// Prioritizes Custom JWT for performance/longevity, falls back to Firebase.
  static Future<String?> getBestToken({bool forceRefresh = false}) async {
    // 1. If force refresh is requested (e.g. after a 401 retry), clear custom tokens
    if (forceRefresh) {
      debugPrint('🛡️ Force refresh requested: Clearing custom session');
      _customAccessToken = null;
      _customRefreshToken = null;
      return await AuthService.getIdToken(forceRefresh: true);
    }

    // 2. Return custom token if we have one (optimized/persisted)
    if (_customAccessToken != null) return _customAccessToken;

    // 3. Fallback to Firebase ID Token
    return await AuthService.getIdToken();
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
  static Future<bool>? _refreshFuture; // Single-flight mutex for token refresh
  static bool _customSessionUnsupported = false;
  static bool _sessionCleared =
      false; // Prevents ghost session restoration after logout

  /// Controller for global authentication failures (e.g. persistent 401s)
  static final StreamController<void> authFailureController =
      StreamController<void>.broadcast();

  /// Exchanges a Firebase ID Token for a custom Access/Refresh Token pair.
  /// Deduplicated to prevent concurrent sync calls.
  static Future<void> syncCustomTokens() async {
    if (_customSessionUnsupported) return;
    _sessionCleared = false; // Fresh login resets the logout guard

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

      final response = await BackendService.instance._sendRequest((
        token,
      ) async {
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
            : (rawError is Map<String, dynamic>
                  ? (rawError['message']?.toString() ?? 'unknown')
                  : 'unknown');

        if (response.statusCode == 500 &&
            errorMessage.toLowerCase().contains('configuration')) {
          _customSessionUnsupported = true;
          _customAccessToken = null;
          _customRefreshToken = null;
          debugPrint(
            '⚠️ Custom JWT backend not configured; using Firebase auth only.',
          );
          return;
        }

        debugPrint(
          '❌ Custom session sync failed: ${response.statusCode} - ${response.body}',
        );
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
      final response = await requestFn(
        _customAccessToken!,
      ).timeout(const Duration(seconds: 30));
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

    final response = await requestFn(
      firebaseToken,
    ).timeout(const Duration(seconds: 30));

    // We NO LONGER call syncCustomTokens() here to prevent side-effect loops.
    // Sync should be orchestrated by the AuthState listener or an explicit login call.

    if (response.statusCode == 401 && !retried) {
      debugPrint('🔄 Auth 401: Attempting Firebase token forced refresh...');
      final newToken = await AuthService.getIdToken(forceRefresh: true);
      if (newToken != null) {
        debugPrint('✅ Firebase token refreshed, retrying request...');
        return await _sendRequest(requestFn, retried: true);
      } else {
        debugPrint('❌ Firebase token refresh failed: User signed out?');
        authFailureController.add(null);
      }
    } else if (response.statusCode == 401 && retried) {
      debugPrint(
        '🚨 Auth 401 persists after retry. Backend is rejecting fresh token.',
      );
      authFailureController.add(null);
    } else if (response.statusCode == 403) {
      debugPrint('🚫 Auth 403: Forbidden. Local session might be corrupt.');
      authFailureController.add(null);
    } else if (response.statusCode == 414 && !retried) {
      // Request entity too large (URL too long) - clear seen IDs and retry
      debugPrint(
        '🔗 HTTP 414: URL too long. Clearing seenIds cache and retrying...',
      );
      FeedSession.instance.resetAll();
      return await _sendRequest(requestFn, retried: true);
    }
    return response;
  }

  static void clearSession() {
    _sessionCleared = true; // Signal in-flight refresh to abort
    _customAccessToken = null;
    _customRefreshToken = null;
    _syncFuture = null;
    _refreshFuture = null;
    _customSessionUnsupported = false;
    debugPrint('🛡️ Custom session tokens cleared');
  }

  /// Single-flight token refresh.
  /// If 3 requests hit 401 simultaneously, only ONE refresh call is made.
  /// All 3 callers await the same Future<bool>.
  Future<bool> _refreshCustomToken() async {
    if (_customRefreshToken == null) return false;

    // If a refresh is already in-flight, piggyback on it
    if (_refreshFuture != null) return _refreshFuture!;

    _refreshFuture = _performRefresh();
    try {
      return await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<bool> _performRefresh() async {
    try {
      final response = await http
          .post(
            Uri.parse('${MediaUploadService.baseUrl}/api/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': _customRefreshToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // CRITICAL: If user logged out while this HTTP call was in-flight,
        // do NOT write new tokens. That would resurrect a dead session.
        if (_sessionCleared) {
          debugPrint(
            '⚠️ Refresh succeeded but session was cleared during flight. Discarding tokens.',
          );
          return false;
        }
        final body = jsonDecode(response.body);
        _customAccessToken = body['data']['accessToken'];
        _customRefreshToken = body['data']['refreshToken'];
        debugPrint('🛡️ Custom session rotated successfully');
        return true;
      }

      // Refresh token itself is invalid/expired → force full re-auth
      if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint('🚨 Refresh token rejected by server. Clearing session.');
        _customAccessToken = null;
        _customRefreshToken = null;
      }
      return false;
    } catch (e) {
      debugPrint('🚨 Token refresh network error: $e');
      return false;
    }
  }

  ApiResponse<T> _processResponse<T>(
    http.Response response,
    T Function(dynamic data) mapper,
  ) {
    try {
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (kDebugMode)
          debugPrint('🚨 GLOBAL AUTH FAILURE: ${response.statusCode}');
        AuthEventStream.emitSessionExpired();
      }
      final Map<String, dynamic> body = jsonDecode(response.body);
      final apiResponse = ApiResponse<T>.fromJson(body, mapper);

      // If backend explicitly says success=false but ApiResponse didn't catch a nice message
      if (!apiResponse.success &&
          (apiResponse.error == null || apiResponse.error!.isEmpty)) {
        return ApiResponse<T>(
          success: false,
          error: 'Something went wrong. Please try again.',
          errorCode: 'SERVER_ERROR',
        );
      }
      return apiResponse;
    } catch (e) {
      debugPrint('API Error: ${response.statusCode} - ${response.body}');
      return ApiResponse<T>(
        success: false,
        error: 'Unable to connect. Please check your internet connection.',
        errorCode: 'NETWORK_ERROR',
      );
    }
  }

  // --- Implementations ---

  Future<ApiResponse<Map<String, dynamic>>> createPost(
    Map<String, dynamic> data,
  ) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/posts'),
          headers: await _getHeaders(token),
          body: jsonEncode(data),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getPost(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/posts/$postId'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getProfile(String uid) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/profiles/$uid'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> updateProfile(Map<String, dynamic> data) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.patch(
          Uri.parse('$_baseUrl/api/profiles/me'),
          headers: await _getHeaders(token),
          body: jsonEncode(data),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> toggleLike(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/like'),
          headers: await _getHeaders(token),
          body: jsonEncode({'postId': postId}),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> addComment(
    String postId,
    String text, {
    String? parentId,
  }) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/comment'),
          headers: await _getHeaders(token),
          body: jsonEncode({
            'postId': postId,
            'text': text,
            if (parentId != null) 'parentId': parentId,
          }),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> toggleCommentLike(String commentId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/comments/$commentId/like'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> toggleFollow(String targetUserId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/follow'),
          headers: await _getHeaders(token),
          body: jsonEncode({'targetUserId': targetUserId}),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> toggleEventJoin(String eventId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/event/join'),
          headers: await _getHeaders(token),
          body: jsonEncode({'eventId': eventId}),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> deletePost(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.delete(
          Uri.parse('$_baseUrl/api/posts/$postId'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> updatePost(
    String postId,
    Map<String, dynamic> data,
  ) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.patch(
          Uri.parse('$_baseUrl/api/posts/$postId'),
          headers: await _getHeaders(token),
          body: jsonEncode(data),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getMessages(String eventId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/posts/$eventId/messages'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> sendEventMessage(
    String eventId,
    String text,
  ) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/posts/$eventId/messages'),
          headers: await _getHeaders(token),
          body: jsonEncode({'text': text}),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getPosts({
    required String feedType,
    int limit = 15,
    double? lat,
    double? lng,
    String? city,
    String? country,
    String? watchedIds,
    String? mediaType,
    String? sid,
    Map<String, dynamic>? cursor,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts').replace(
        queryParameters: {
          if (city != null) 'city': city,
          if (country != null) 'country': country,
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
          if (feedType != null) 'feedType': feedType,
          if (watchedIds != null) 'watchedIds': watchedIds,
          if (mediaType != null) 'mediaType': mediaType,
          if (sid != null) 'sid': sid,
          if (cursor != null) 'cursor': jsonEncode(cursor),
          'limit': limit.toString(),
        },
      );
      if (kDebugMode) debugPrint('🚀 API REQUEST: $uri');
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getFilteredPosts({
    String? authorId,
    String? category,
    String? city,
    String? country,
    int limit = 15,
    Map<String, dynamic>? cursor,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts').replace(
        queryParameters: {
          if (authorId != null) 'authorId': authorId,
          if (category != null) 'category': category,
          if (city != null) 'city': city,
          if (country != null) 'country': country,
          if (cursor != null) 'cursor': jsonEncode(cursor),
          'limit': limit.toString(),
        },
      );
      if (kDebugMode) debugPrint('🚀 API FILTERED REQUEST: $uri');
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getComments(
    String postId, {
    String? afterId,
    int limit = 20,
    String sort = 'newest',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/interactions/comments/$postId')
          .replace(
            queryParameters: {
              'limit': limit.toString(),
              if (afterId != null) 'afterId': afterId,
              'sort': sort,
            },
          );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getReplies(
    String commentId, {
    String? afterId,
    int limit = 10,
  }) async {
    try {
      final uri =
          Uri.parse(
            '$_baseUrl/api/interactions/comments/$commentId/replies',
          ).replace(
            queryParameters: {
              'limit': limit.toString(),
              if (afterId != null) 'afterId': afterId,
            },
          );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> search({
    required String query,
    String type = 'posts',
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search').replace(
        queryParameters: {'q': query, 'type': type, 'limit': limit.toString()},
      );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) {
        // Handle both old format (List) and new format ({users:[], posts:[]})
        if (d is List) return d;
        if (d is Map<String, dynamic>) return d[type] as List<dynamic>? ?? [];
        return [];
      });
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> searchAll({
    required String query,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search').replace(
        queryParameters: {'q': query, 'type': 'all', 'limit': limit.toString()},
      );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getNotifications({String? type}) async {
    try {
      final queryParams = type != null ? '?type=$type' : '';
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/notifications$queryParams'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> markNotificationAsRead(String id) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.patch(
          Uri.parse('$_baseUrl/api/notifications/$id/read'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<int>> markAllNotificationsAsRead() async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.patch(
          Uri.parse('$_baseUrl/api/notifications/read-all'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d['count'] as int? ?? 0);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> checkLikeState(
    String postId,
  ) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/interactions/likes/check',
      ).replace(queryParameters: {'postId': postId});
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<http.Response> _sendUnauthenticatedRequest(
    Future<http.Response> Function() requestFn,
  ) async {
    return await requestFn().timeout(const Duration(seconds: 30));
  }

  Future<ApiResponse<bool>> checkFollowState(String targetUserId) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/interactions/follows/check',
      ).replace(queryParameters: {'targetUserId': targetUserId});
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d['followed'] == true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> checkUsername(String username) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/profiles/check-username',
      ).replace(queryParameters: {'username': username});
      debugPrint('🔍 checkUsername checking: $username via $uri');
      final resp = await _sendUnauthenticatedRequest(
        () async => await _client.get(
          uri,
          headers: {'Content-Type': 'application/json'},
        ),
      );
      debugPrint(
        '🔍 checkUsername response: ${resp.statusCode} body: ${resp.body}',
      );
      return _processResponse(resp, (d) => d['available'] == true);
    } catch (e) {
      debugPrint('🚨 checkUsername error: $e');
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> checkEventAttendance(String eventId) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/api/interactions/events/check',
      ).replace(queryParameters: {'eventId': eventId});
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d['attending'] == true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<String>>> getMyEventIds() async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/interactions/events/my-events'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) {
        final ids = d['eventIds'] as List<dynamic>;
        return ids.map((e) => e.toString()).toList();
      });
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> trackPostView(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/posts/$postId/view'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getPostInsights(
    String postId,
  ) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/posts/$postId/insights'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> muteUser(String userId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/profiles/mute/$userId'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> unmuteUser(String userId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/profiles/unmute/$userId'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> reportPost(String postId, String reason) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/posts/$postId/report'),
          headers: await _getHeaders(token),
          body: jsonEncode({'reason': reason}),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<List<dynamic>>> getNewPostsSince({
    double? lat,
    double? lng,
    String? city,
    required int sinceTimestamp,
    double? maxDistance,
    String? watchedIds,
    String? sid,
    String? mediaType,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts/new-since').replace(
        queryParameters: {
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
          if (city != null) 'city': city,
          'sinceTimestamp': sinceTimestamp.toString(),
          if (maxDistance != null) 'maxDistance': maxDistance.toString(),
          if (watchedIds != null) 'watchedIds': watchedIds,
          if (sid != null) 'sid': sid,
          if (mediaType != null) 'mediaType': mediaType,
        },
      );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> savePost(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/interactions/save'),
          headers: await _getHeaders(token),
          body: jsonEncode({'postId': postId}),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> unsavePost(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.delete(
          Uri.parse('$_baseUrl/api/interactions/save/$postId'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> hidePost(String postId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/posts/$postId/hide'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  // --- Chat Methods ---

  Future<ApiResponse<List<dynamic>>> getChats() async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.get(
          Uri.parse('$_baseUrl/api/chats'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> getOrCreateChat(
    String targetUserId,
  ) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/chats'),
          headers: await _getHeaders(token),
          body: jsonEncode({'targetUserId': targetUserId}),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> sendChatMessage({
    required String chatId,
    required String text,
  }) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/chats/$chatId/messages'),
          headers: await _getHeaders(token),
          body: jsonEncode({'text': text}),
        ),
      );
      return _processResponse(resp, (d) => d as Map<String, dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  Future<ApiResponse<bool>> markChatAsRead(String chatId) async {
    try {
      final resp = await _sendRequest(
        (token) async => await _client.post(
          Uri.parse('$_baseUrl/api/chats/$chatId/read'),
          headers: await _getHeaders(token),
        ),
      );
      return _processResponse(resp, (_) => true);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }

  // --- Static Proxies ---
  Future<void> validateServer() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        debugPrint('⚠️ Backend health check failed: ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('🚨 Backend health check error: $e');
    }
  }

  Future<ApiResponse<List<dynamic>>> getExplore({
    double? lat,
    double? lng,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/posts/explore').replace(
        queryParameters: {
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
          'limit': limit.toString(),
        },
      );
      final resp = await _sendRequest(
        (token) async =>
            await _client.get(uri, headers: await _getHeaders(token)),
      );
      return _processResponse(resp, (d) => d as List<dynamic>);
    } catch (e) {
      return ApiResponse(success: false, error: e.toString());
    }
  }
}
