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
      final dynamic rawError = json['error'];
      String message = 'An unknown error occurred';
      String code = 'INTERNAL_ERROR';

      if (rawError is Map<String, dynamic>) {
        message = rawError['message']?.toString() ?? message;
        code = rawError['code']?.toString() ?? code;
      } else if (rawError is String && rawError.trim().isNotEmpty) {
        message = rawError;
      } else if (json['message'] is String) {
        message = json['message'] as String;
      }

      return ApiResponse(success: false, error: message, errorCode: code);
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
  final bool hasMore;
  final String? cursor;

  ApiResponsePagination({this.hasMore = false, this.cursor});

  factory ApiResponsePagination.fromJson(Map<String, dynamic> json) {
    return ApiResponsePagination(
      hasMore: json['hasMore'] as bool? ?? false,
      cursor: json['cursor']?.toString() ?? json['nextCursor']?.toString(),
    );
  }
}
