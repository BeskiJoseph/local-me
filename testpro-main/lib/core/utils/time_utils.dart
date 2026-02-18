// Shared time formatting utilities used across the app.
//
// Replaces duplicate `_formatTimeAgo()` implementations from:
// - `widgets/post_card.dart`
// - `screens/home_screen.dart`

class TimeUtils {
  TimeUtils._(); // Prevent instantiation

  /// Formats a [DateTime] into a human-readable relative time string.
  ///
  /// Examples: "Just now", "5m ago", "3h ago", "2d ago", "12/1/2025"
  static String formatTimeAgo(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// Compact variant without "ago" suffix. Used in Nextdoor-style cards.
  ///
  /// Examples: "5m", "3h", "2d", "1/15"
  static String formatTimeAgoCompact(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d';
    } else {
      return '${timestamp.month}/${timestamp.day}';
    }
  }

  /// Simple date formatting.
  ///
  /// Example: "15/1 14:30"
  static String formatDate(DateTime date) {
    return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
