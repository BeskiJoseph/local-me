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

      // 1. Fetch current profile
      final response = await BackendService.getProfile(user.uid);
      String? existingLocation;
      if (response.success && response.data != null) {
        existingLocation = response.data!['location'] as String?;
      }
      
      // UX Hardening: If location already exists and not forceSync, we still need coordinates
      // for the geo-feed, but we won't overwrite the city name in the profile unless forced.
      if (existingLocation != null && existingLocation.isNotEmpty && !forceSync) {
        final parts = existingLocation.split(',');
        _cachedCity = parts[0].trim();
        if (parts.length > 1) _cachedCountry = parts[1].trim();

        // If we already have coordinates, we can truly skip
        if (_cachedPosition != null) {
           if (kDebugMode) debugPrint('📍 Location and coordinates already cached. Skipping.');
           return;
        }
        if (kDebugMode) debugPrint('📍 Location set to "$existingLocation" but missing coordinates. Fetching GPS...');
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

      // 3. Get accurate position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      _cachedPosition = position;

      // 4. Geocode
      final place = await GeocodingService.getPlace(position.latitude, position.longitude);
      _cachedCity = place['city'] ?? _cachedCity;
      _cachedCountry = place['country'] ?? _cachedCountry;

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
