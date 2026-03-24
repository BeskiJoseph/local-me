class PaginatedResponse<T> {
  final List<T> data;
  final bool hasMore;
  final int? total;
  final Map<String, dynamic>? cursor;

  PaginatedResponse({
    required this.data,
    this.hasMore = false,
    this.total,
    this.cursor,
  });

  PaginatedResponse<T> copyWith({
    List<T>? data,
    bool? hasMore,
    int? total,
    Map<String, dynamic>? cursor,
  }) {
    return PaginatedResponse<T>(
      data: data ?? this.data,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
      cursor: cursor ?? this.cursor,
    );
  }
}
