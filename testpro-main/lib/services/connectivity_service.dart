import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Central service to monitor and react to network status changes.
class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();

  /// Stream of boolean values indicating whether the internet is connected.
  static Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Returns true if currently connected to a network.
  static Future<bool> isConnected() async {
    final results = await _connectivity.checkConnectivity();
    return !results.contains(ConnectivityResult.none);
  }

  /// Initialize the connectivity listener.
  static void initialize() {
    _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final connected = !results.contains(ConnectivityResult.none);
      _connectivityController.add(connected);
      debugPrint('🌐 Network status changed: ${connected ? "CONNECTED" : "OFFLINE"}');
    });
  }

  /// Helper to show a persistent offline banner in the current Scaffold.
  static void showOfflineBanner(BuildContext context) {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.white),
            SizedBox(width: 12),
            Text(
              'No internet connection. Using offline data.',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('DISMISS', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Hide the offline banner.
  static void hideOfflineBanner(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }
}
