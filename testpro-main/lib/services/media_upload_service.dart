import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';
import 'backend_service.dart';

/// Client-side wrapper for uploading media to your backend,
/// which then talks to Cloudflare R2 securely.
///
/// IMPORTANT:
/// - The backend endpoint must:
///   - Verify the Firebase ID token from the Authorization header.
///   - Upload the file to R2 using server-side credentials.
///   - Return JSON: { "url": "<public_media_url>" }.
class MediaUploadService {
  /// Base URL for backend API
  /// 
  /// Configure via --dart-define=API_URL=https://your-api.com
  /// Production deployments MUST set this environment variable.
  static String? _cachedBaseUrl;
  
  static String get baseUrl {
    // Return cached value if available
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }
    
    // 1. Prioritize build-time configuration (Production & CI/CD)
    // 1. Resolve base URL from environment variable or default
    const String defaultBaseUrl = 'http://10.211.157.94:4000'; // Physical device IP
    String url = const String.fromEnvironment('API_URL', defaultValue: defaultBaseUrl);
    
    // 2. Automatic Android emulator loopback detection (ONLY if using localhost)
    if (!kIsWeb && 
        defaultTargetPlatform == TargetPlatform.android && 
        url.contains('localhost')) {
      url = 'http://10.0.2.2:4000';
      if (kDebugMode) debugPrint('🤖 Android Emulator detected, using 10.0.2.2:4000');
    }

    _cachedBaseUrl = url;
    if (kDebugMode) debugPrint('🔗 Backend URL: $_cachedBaseUrl');
    return _cachedBaseUrl!;
  }

  // ──────────────────────────────────────────────
  // Upload Size Limits
  // ──────────────────────────────────────────────
  static const int _maxImageBytes = 10 * 1024 * 1024;  // 10 MB
  static const int _maxVideoBytes = 50 * 1024 * 1024;  // 50 MB

  static Future<String?> _upload({
    required Uint8List data,
    required String fileExtension,
    required String mediaType,
    required String path, // e.g. "/api/upload/profile" or "/api/upload/post"
    Map<String, String>? extraFields,
    bool isRetry = false,
  }) async {
    // 0. Validate file size BEFORE network call
    final maxBytes = mediaType == 'video' ? _maxVideoBytes : _maxImageBytes;
    if (data.length > maxBytes) {
      final sizeMB = (data.length / (1024 * 1024)).toStringAsFixed(1);
      final limitMB = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw Exception(
        '${mediaType == 'video' ? 'Video' : 'Image'} is too large ($sizeMB MB). Maximum allowed: $limitMB MB.',
      );
    }

    // 1. Get current best token (Custom Access Token or Firebase ID Token fallback)
    final token = await BackendClient.getBestToken(forceRefresh: isRetry);
    if (token == null) {
      throw StateError('User must be signed in to upload media.');
    }
    
    if (kDebugMode && token.length > 20) {
      debugPrint('🔑 Auth Token: ${token.substring(0, 10)}...${token.substring(token.length - 10)}');
    }

    final uri = Uri.parse('$baseUrl$path');
    if (kDebugMode) debugPrint('Uploading to: $uri');

    // 2. Build Multipart Request
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['mediaType'] = mediaType
      ..fields['fileExtension'] = fileExtension;

    if (extraFields != null) {
      request.fields.addAll(extraFields);
    }

    final mimeType = mediaType == 'video' ? 'video/mp4' : 'image/jpeg';

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        data,
        filename: 'upload.$fileExtension',
        contentType: MediaType(
          mimeType.split('/')[0],
          mimeType.split('/')[1],
        ),
      ),
    );

    // 3. Send Request (Longer timeout for video uploads)
    final timeoutDuration = mediaType == 'video'
        ? const Duration(seconds: 300) // 5 min for videos
        : const Duration(seconds: 120); // 2 min for images
    if (kDebugMode) debugPrint('Sending request${isRetry ? ' (Retry)' : ''}...');
    final streamed = await request.send().timeout(timeoutDuration);
    
    final response = await http.Response.fromStream(streamed);
    if (kDebugMode) debugPrint('Response received: ${response.statusCode}');

    // 4. Handle 401 with Retry
    if (response.statusCode == 401 && !isRetry) {
      if (kDebugMode) debugPrint('🔄 Upload 401: Retrying with forced token refresh...');
      
      // Small cooldown to let Firebase auth catch up or network settle
      await Future.delayed(const Duration(milliseconds: 500));

      return await _upload(
        data: data,
        fileExtension: fileExtension,
        mediaType: mediaType,
        path: path,
        extraFields: extraFields,
        isRetry: true,
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['url'] as String?;
    } else {
      throw Exception(
        'Upload failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Compresses an image to max 1080px width at 75% quality.
  /// Skips compression on web (flutter_image_compress not supported).
  /// Target: < 300KB per image.
  static Future<Uint8List> _compressImage(Uint8List data) async {
    if (kIsWeb) return data; // Web doesn't support flutter_image_compress
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        data,
        minWidth: 1080,
        minHeight: 1080,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      if (kDebugMode) {
        debugPrint('🗜️ Image compressed: ${data.length ~/ 1024}KB → ${compressed.length ~/ 1024}KB');
      }
      return compressed;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Image compression failed, using original: $e');
      return data; // Fallback to original if compression fails
    }
  }

  static Future<String?> uploadProfileImage({
    required String userId,
    required Uint8List data,
    String fileExtension = 'jpg',
  }) async {
    final compressed = await _compressImage(data);
    return _upload(
      data: compressed,
      fileExtension: fileExtension,
      mediaType: 'image',
      path: '/api/upload/profile',
      extraFields: {'userId': userId},
    );
  }

  static Future<String?> uploadPostMedia({
    required String postId,
    required Uint8List data,
    String fileExtension = 'jpg',
    String mediaType = 'image', // 'image' or 'video'
  }) async {
    // Only compress images — videos are handled differently
    final uploadData = mediaType == 'image' ? await _compressImage(data) : data;
    return _upload(
      data: uploadData,
      fileExtension: fileExtension,
      mediaType: mediaType,
      path: '/api/upload/post',
      extraFields: {
        'postId': postId,
      },
    );
  }
}


