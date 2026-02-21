class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final String? errorCode;
  final ApiResponsePagination? pagination;

  ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.errorCode,
    this.pagination,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic) fromJsonT,
  ) {
    final bool success = json['success'] ?? false;
    
    if (!success) {
      final errorMap = json['error'] as Map<String, dynamic>?;
      return ApiResponse(
        success: false,
        error: errorMap?['message'] ?? 'An unknown error occurred',
        errorCode: errorMap?['code'] ?? 'INTERNAL_ERROR',
      );
    }

    return ApiResponse(
      success: true,
      data: json['data'] != null ? fromJsonT(json['data']) : null,
      pagination: json['pagination'] != null 
          ? ApiResponsePagination.fromJson(json['pagination']) 
          : null,
    );
  }
}

class ApiResponsePagination {
  final String? cursor;
  final bool hasMore;

  ApiResponsePagination({
    this.cursor,
    this.hasMore = false,
  });

  factory ApiResponsePagination.fromJson(Map<String, dynamic> json) {
    return ApiResponsePagination(
      cursor: json['cursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}
