class FeedSession {
  FeedSession._();
  static final FeedSession instance = FeedSession._();

  // Unique session ID for server-side seen tracking
  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  String get sessionId => _sessionId;

  // Shared across BOTH local and global tabs to prevent repeat posts
  final Set<String> _seenPostIds = {};
  Set<String> get seenIds => _seenPostIds;

  /// Mark a list of posts as seen in the current app session
  /// Enforces a hard limit of 500 IDs to prevent memory/payload bloat
  void markSeen(List<String> ids) {
    _seenPostIds.addAll(ids);
    
    if (_seenPostIds.length > 500) {
      final list = _seenPostIds.toList();
      final capped = list.sublist(list.length - 500);
      _seenPostIds.clear();
      _seenPostIds.addAll(capped);
    }
  }

  /// Get seen IDs formatted for backend watchedIds parameter
  String get seenIdsParam => _seenPostIds.join(',');

  /// Clear the session seen list (e.g. on manual pull-to-refresh)
  void reset() {
    _seenPostIds.clear();
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  }
}
