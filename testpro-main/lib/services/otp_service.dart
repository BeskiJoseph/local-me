import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'media_upload_service.dart';

class OtpService {
  static String get _baseUrl => MediaUploadService.baseUrl;

  /// Sends an email OTP to the specified email address.
  static Future<void> sendOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/otp/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to send OTP';
        throw Exception(error);
      }
      
      if (kDebugMode) debugPrint("sendOtp Success");
    } catch (e) {
      if (kDebugMode) debugPrint('Error in sendOtp: $e');
      if (e is Exception) rethrow;
      throw Exception('Failed to send OTP. Please check your connection.');
    }
  }

  /// Verifies the OTP for the specified email address.
  static Future<void> verifyOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/otp/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Invalid verification code';
        throw Exception(error);
      }
      
      if (kDebugMode) debugPrint("verifyOtp Success");
    } catch (e) {
      if (kDebugMode) debugPrint('Error in verifyOtp: $e');
      if (e is Exception) rethrow;
      throw Exception('Verification failed. Please try again.');
    }
  }
}
