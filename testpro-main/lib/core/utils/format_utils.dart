// Shared formatting utilities used across the app.
//
// Replaces duplicate formatting logic from:
// - `screens/personal_account.dart` (_formatCount)

class FormatUtils {
  FormatUtils._(); // Prevent instantiation

  /// Formats a number into a compact string.
  ///
  /// Examples: 999 → "999", 1000 → "1.0k", 15432 → "15.4k"
  static String formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
