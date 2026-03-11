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

  PaginatedResponse<T> copyWith({
    List<T>? data,
    String? nextCursor,
    bool? hasMore,
    int? total,
    double? lastDistance,
    String? lastPostId,
    String? fallbackLevel,
  }) {
    return PaginatedResponse<T>(
      data: data ?? this.data,
      nextCursor: nextCursor ?? this.nextCursor,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
      lastDistance: lastDistance ?? this.lastDistance,
      lastPostId: lastPostId ?? this.lastPostId,
      fallbackLevel: fallbackLevel ?? this.fallbackLevel,
    );
  }
}
