import '../models/post.dart';

class PaginatedResponse<T> {
  final List<T> data;
  final String? nextCursor;
  final bool hasMore;
  final int? total;

  PaginatedResponse({
    required this.data, 
    this.nextCursor,
    this.hasMore = false,
    this.total,
  });
}
