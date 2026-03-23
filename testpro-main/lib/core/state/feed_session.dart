import 'package:uuid/uuid.dart';

class FeedSession {
  FeedSession._();
  static final FeedSession instance = FeedSession._();

  // Unique session ID for server-side seen tracking (UUID-based, collision-resistant)
  String _sessionId = const Uuid().v4();
  String get sessionId => _sessionId;

  // Separate seen IDs per feed type to prevent cross-tab contamination
  final Map<String, Set<String>> _seenIdsByFeed = {};

  /// Get the seen set for a specific feed type
  Set<String> _getSeenSet(String feedType) {
    return _seenIdsByFeed.putIfAbsent(feedType, () => {});
  }

  /// Mark a list of posts as seen for specific feed type
  /// Enforces a hard limit of 50 IDs to keep URL < 2KB when encoded
  void markSeen(List<String> ids, {String feedType = 'global'}) {
    final set = _getSeenSet(feedType);
    set.addAll(ids);

    // Cap at 50 to keep URL < 2KB when encoded (down from 500)
    if (set.length > 50) {
      final list = set.toList();
      final capped = list.sublist(list.length - 50);
      set.clear();
      set.addAll(capped);
    }
  }

  /// Get seen IDs formatted for backend watchedIds parameter for specific feed type
  String seenIdsParam(String feedType) => _getSeenSet(feedType).join(',');

  /// Get all seen IDs for a specific feed type (for testing/debugging)
  Set<String> getSeenIds(String feedType) => _getSeenSet(feedType);

  /// Clear the session seen list for specific feed (e.g. on manual pull-to-refresh)
  void reset(String feedType) {
    _seenIdsByFeed.remove(feedType);
  }

  /// Full reset - clear all feeds and regenerate session ID
  void resetAll() {
    _seenIdsByFeed.clear();
    _sessionId = const Uuid().v4();
  }
}
