class FeedSession {
  FeedSession._();
  static final FeedSession instance = FeedSession._();

  // Shared across BOTH local and global tabs to prevent repeat posts
  final Set<String> _seenPostIds = {};

  /// Mark a list of posts as seen in the current app session
  void markSeen(List<String> ids) {
    _seenPostIds.addAll(ids);
  }

  /// Get seen IDs formatted for backend watchedIds parameter
  /// Limited to last 100 to avoid URL length issues
  String get seenIdsParam {
    final list = _seenPostIds.toList();
    final recent = list.length > 100 ? list.sublist(list.length - 100) : list;
    return recent.join(',');
  }

  /// Clear the session seen list (e.g. on manual pull-to-refresh)
  void reset() {
    _seenPostIds.clear();
  }
}
