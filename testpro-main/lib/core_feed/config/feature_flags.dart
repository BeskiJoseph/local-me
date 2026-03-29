/// Feature flags for the new core_feed system.
/// This allows for a safe, parallel rollout without breaking the legacy app.
class FeatureFlags {
  /// Set to true to enable the new core_feed architecture.
  /// Set to false to keep using the legacy feed system.
  static const bool useNewFeed = true;
}
