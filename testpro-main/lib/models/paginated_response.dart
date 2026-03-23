class PaginatedResponse<T> {
  final List<T> data;
  final bool hasMore;
  final int? total;

  PaginatedResponse({required this.data, this.hasMore = false, this.total});

  PaginatedResponse<T> copyWith({List<T>? data, bool? hasMore, int? total}) {
    return PaginatedResponse<T>(
      data: data ?? this.data,
      hasMore: hasMore ?? this.hasMore,
      total: total ?? this.total,
    );
  }
}
