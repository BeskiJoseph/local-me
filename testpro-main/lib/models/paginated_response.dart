class PaginatedResponse<T> {
  final List<T> data;
  final String? nextCursor;
  final bool hasMore;
  final int? total;
  
  // V2 Distance Cursors (for local feed)
  final double? lastDistance;
  final String? lastPostId;
  final String? fallbackLevel;

  PaginatedResponse({
    required this.data, 
    this.nextCursor,
    this.hasMore = false,
    this.total,
    this.lastDistance,
    this.lastPostId,
    this.fallbackLevel,
  });
}
