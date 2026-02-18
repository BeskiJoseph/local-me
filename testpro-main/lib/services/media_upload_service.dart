import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  static String get baseUrl {
    // 1. Prioritize build-time configuration (Production & CI/CD)
    const apiUrl = String.fromEnvironment('API_URL');
    if (apiUrl.isNotEmpty) {
      return apiUrl;
    }

    // 2. Default to localhost for development
    // ⚠️ Update this to your actual production backend URL for production builds
    const defaultUrl = 'http://localhost:4000';
    
    if (kDebugMode) {
       debugPrint('ℹ️ Using default API URL: $defaultUrl');
       debugPrint('ℹ️ Set API_URL via --dart-define=API_URL=... for custom backend');
    }
    
    return defaultUrl;
  }

  static Future<String?> _upload({
    required Uint8List data,
    required String fileExtension,
    required String mediaType,
    required String path, // e.g. "/api/upload/profile" or "/api/upload/post"
    Map<String, String>? extraFields,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to upload media.');
    }

    if (kDebugMode) debugPrint('Getting Firebase ID token...');
    final idToken = await user.getIdToken();
    if (kDebugMode) debugPrint('Got Firebase ID token');
    
    final uri = Uri.parse('$baseUrl$path');
    if (kDebugMode) debugPrint('Uploading to: $uri');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $idToken'
      ..fields['mediaType'] = mediaType
      ..fields['fileExtension'] = fileExtension;

    if (extraFields != null) {
      request.fields.addAll(extraFields);
    }

    // Determine MIME type based on media type and extension
    final mimeType = mediaType == 'video' 
      ? 'video/mp4'
      : 'image/jpeg'; // Default to JPEG for images

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

    if (kDebugMode) debugPrint('Sending request...');
    final streamed = await request.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Upload request timeout after 30 seconds');
      },
    );
    
    if (kDebugMode) debugPrint('Got response, reading body...');
    final response = await http.Response.fromStream(streamed);
    if (kDebugMode) debugPrint('Response received: ${response.statusCode}');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['url'] as String?;
    } else {
      // You may want to log the full body/status in a real app.
      throw Exception(
        'Upload failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  static Future<String?> uploadProfileImage({
    required String userId,
    required Uint8List data,
    String fileExtension = 'jpg',
  }) {
    return _upload(
      data: data,
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
  }) {
    return _upload(
      data: data,
      fileExtension: fileExtension,
      mediaType: mediaType,
      path: '/api/upload/post',
      extraFields: {
        'postId': postId,
      },
    );
  }
}


