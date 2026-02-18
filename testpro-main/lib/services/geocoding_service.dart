import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GeocodingService {
  // Using BigDataCloud Free API (Client-side friendly, CORS allowed)
  static const String _baseUrl = 'https://api.bigdatacloud.net/data/reverse-geocode-client';
  
  static Future<Map<String, String?>> getPlace(double lat, double lng) async {
    try {
      final uri = Uri.parse('$_baseUrl?latitude=$lat&longitude=$lng&localityLanguage=en');
      
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // BigDataCloud fields
        String? city = data['city'] ?? data['locality'];
        String? country = data['countryName'];
        
        // Fallback for city if empty (sometimes returns empty string)
        if (city != null && city.isEmpty) city = null;
        city ??= data['principalSubdivision'];

        return {
          'city': city,
          'country': country,
          'full_location': '${city ?? "Unknown"}, ${country ?? "Unknown"}'
        };
      }
    } catch (e) {
      debugPrint('Geocoding Error: $e');
    }
    return {'city': null, 'country': null, 'full_location': null};
  }
}
