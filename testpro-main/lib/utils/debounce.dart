import 'dart:async';
import 'package:flutter/foundation.dart';

/// Utility class for debouncing function calls
/// Eliminates code duplication for debounce patterns across the app
class Debounce {
  static final Map<String, Timer?> _timers = {};

  /// Debounce a function call with the specified delay
  /// 
  /// [key] - Unique identifier for this debounce operation
  /// [action] - Function to execute after delay
  /// [delay] - Time to wait before executing (default: 300ms)
  /// 
  /// Example:
  /// ```dart
  /// Debounce.run('search', () {
  ///   performSearch(query);
  /// }, delay: Duration(milliseconds: 500));
  /// ```
  static void run(
    String key,
    VoidCallback action, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    // Cancel any existing timer for this key
    _timers[key]?.cancel();
    
    // Create new timer
    _timers[key] = Timer(delay, () {
      action();
      _timers.remove(key);
    });
  }

  /// Cancel a specific debounce operation
  static void cancel(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  /// Cancel all active debounce operations
  static void cancelAll() {
    for (final timer in _timers.values) {
      timer?.cancel();
    }
    _timers.clear();
  }

  /// Check if a debounce operation is currently active
  static bool isActive(String key) {
    return _timers.containsKey(key) && _timers[key]?.isActive == true;
  }

  /// Get the number of active debounce operations
  static int get activeCount => _timers.length;

  /// Dispose of all timers (call this in dispose methods)
  static void dispose() {
    cancelAll();
  }
}

/// A debouncer that can be used as a field in a class
/// Useful when you need a dedicated debouncer instance
class Debouncer {
  Timer? _timer;
  final Duration delay;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  /// Run the action after the delay, cancelling any previous call
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancel the current debounce
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Check if currently waiting to execute
  bool get isActive => _timer?.isActive == true;

  /// Dispose the debouncer
  void dispose() {
    cancel();
  }
}

/// Extension to make debouncing easier on functions
extension DebounceExtension on VoidCallback {
  /// Create a debounced version of this function
  VoidCallback debounced({
    Duration delay = const Duration(milliseconds: 300),
    String? key,
  }) {
    return () {
      if (key != null) {
        Debounce.run(key, this, delay: delay);
      } else {
        // Use a random key if none provided
        final randomKey = 'debounce_${DateTime.now().millisecondsSinceEpoch}';
        Debounce.run(randomKey, this, delay: delay);
      }
    };
  }
}

/// Mixin for classes that need debounce functionality
mixin DebounceMixin {
  final Map<String, Timer?> _debounceTimers = {};

  /// Debounce a function with a key
  void debounce(
    String key,
    VoidCallback action, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(delay, () {
      action();
      _debounceTimers.remove(key);
    });
  }

  /// Cancel a specific debounce
  void cancelDebounce(String key) {
    _debounceTimers[key]?.cancel();
    _debounceTimers.remove(key);
  }

  /// Cancel all debounces
  void cancelAllDebounces() {
    for (final timer in _debounceTimers.values) {
      timer?.cancel();
    }
    _debounceTimers.clear();
  }

  /// Check if a debounce is active
  bool isDebounceActive(String key) {
    return _debounceTimers.containsKey(key) && _debounceTimers[key]?.isActive == true;
  }

  /// Must be called in dispose method
  @mustCallSuper
  void disposeDebounces() {
    cancelAllDebounces();
  }
}
