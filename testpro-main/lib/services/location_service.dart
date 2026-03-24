import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'geocoding_service.dart';
import 'backend_service.dart';
import 'auth_service.dart';

class LocationService {
  static String? _cachedCity;
  static String? _cachedCountry;
  static Position? _cachedPosition;
  static bool _isDetecting = false;
  static Completer<void>? _detectionCompleter;

  static String? get currentCity => _cachedCity;
  static String? get currentCountry => _cachedCountry;
  static Position? get currentPosition => _cachedPosition;

  /// Detect current location and sync with backend
  static Future<void> detectLocation({bool forceSync = false}) async {
    if (_isDetecting) {
      return _detectionCompleter?.future ?? Future.value();
    }
    _isDetecting = true;
    _detectionCompleter = Completer<void>();

    try {
      final user = AuthService.currentUser;
      if (user == null) return;

      // 1. Fetch current profile to see what's already saved
      final response = await BackendService.getProfile(user.uid);
      String? existingCity;
      String? existingCountry;
      if (response.success && response.data != null) {
        final existingLocation = response.data!['location'] as String?;
        if (existingLocation != null && existingLocation.isNotEmpty) {
           final parts = existingLocation.split(',');
           existingCity = parts[0].trim();
           if (parts.length > 1) existingCountry = parts[1].trim();
        }
      }
      
      // If we already have coordinates AND a city, and no forceSync, we can skip
      if (_cachedPosition != null && _cachedCity != null && !forceSync) {
         if (kDebugMode) debugPrint('📍 Location and coordinates already cached. Skipping.');
         return;
      }

      // 2. Check permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      // 3. Get accurate position (High Accuracy for reliability)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      _cachedPosition = position;

      // 4. Geocode to get fresh city name
      final place = await GeocodingService.getPlace(position.latitude, position.longitude);
      _cachedCity = place['city'] ?? existingCity;
      _cachedCountry = place['country'] ?? existingCountry;

      // 5. Sync to backend
      if (_cachedCity != null) {
        final locationStr = _cachedCountry != null 
            ? '$_cachedCity, $_cachedCountry' 
            : _cachedCity!;
        
        await BackendService.updateProfile({'location': locationStr});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Location service error: $e');
    } finally {
      _isDetecting = false;
      _detectionCompleter?.complete();
      _detectionCompleter = null;
    }
  }

  static String getLocationString() {
    if (_cachedCity == null) return 'Local';
    return _cachedCountry != null ? '$_cachedCity, $_cachedCountry' : _cachedCity!;
  }
}
