import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'geocoding_service.dart';
import 'backend_service.dart';
import 'auth_service.dart';

class LocationService {
  static String? _cachedCity;
  static String? _cachedCountry;
  static bool _isDetecting = false;

  static String? get currentCity => _cachedCity;
  static String? get currentCountry => _cachedCountry;

  /// Detect current location and sync with backend
  static Future<void> detectLocation({bool forceSync = false}) async {
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final user = AuthService.currentUser;
      if (user == null) return;

      // 1. Fetch current profile
      final response = await BackendService.getProfile(user.uid);
      String? existingLocation;
      if (response.success && response.data != null) {
        existingLocation = response.data!['location'] as String?;
      }
      
      // UX Hardening: If location already exists and not forceSync, ask "Why overwrite?"
      // In this logic, we skip auto-sync if location is already set, 
      // unless it's the first time or explicitly asked.
      if (existingLocation != null && existingLocation.isNotEmpty && !forceSync) {
        if (kDebugMode) debugPrint('📍 Location already set to "$existingLocation". Skipping auto-detection to protect user choice.');
        
        // Load existing into cache even if we don't detection
        final parts = existingLocation.split(',');
        _cachedCity = parts[0].trim();
        if (parts.length > 1) _cachedCountry = parts[1].trim();
        
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

      // 3. Get accurate position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );

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
      debugPrint('Location service error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  static String getLocationString() {
    if (_cachedCity == null) return 'Local';
    return _cachedCountry != null ? '$_cachedCity, $_cachedCountry' : _cachedCity!;
  }
}
