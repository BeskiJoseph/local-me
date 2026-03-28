/// Centralized feed configuration constants
/// 
/// All feed-related constants should be defined here to avoid
/// hardcoded values scattered throughout the codebase.
class FeedConstants {
  // Prevent instantiation
  FeedConstants._();

  /// Default page size for feed pagination
  static const int defaultPageSize = 15;

  /// Initial load limit for home feed
  static const int initialLoadLimit = 20;

  /// Feed type identifiers
  static const String feedTypeGlobal = 'global';
  static const String feedTypeLocal = 'local';
  static const String feedTypeHybrid = 'hybrid';
  static const String feedTypeReels = 'reels';
  static const String feedTypeDetail = 'detail';
  static const String feedTypeProfile = 'profile';

  /// Retry configuration
  static const int maxRetries = 3;
  static const int retryDelayMs = 500;

  /// Scroll threshold for pagination (pixels from bottom)
  static const double scrollThreshold = 600;

  /// Animation durations
  static const int pageTransitionMs = 300;
}
