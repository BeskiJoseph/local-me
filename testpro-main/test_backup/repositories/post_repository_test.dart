import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/post_repository.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/models/api_response.dart';
import 'package:http/http.dart' as http;

class ManualMockBackendClient extends BackendClient {
  ApiResponse? mockResponse;
  Map<String, dynamic>? lastData;
  String? lastId;

  @override
  Future<ApiResponse<String>> createPost(Map<String, dynamic> data) async {
    lastData = data;
    return (mockResponse as ApiResponse<String>?) ?? ApiResponse.success("mock_id");
  }

  @override
  Future<ApiResponse<bool>> deletePost(String postId) async {
    lastId = postId;
    return (mockResponse as ApiResponse<bool>?) ?? ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<List<dynamic>>> getFeed({String? cursor, int limit = 10, String type = 'discovery'}) async {
    return (mockResponse as ApiResponse<List<dynamic>>?) ?? ApiResponse.success([]);
  }
}

void main() {
  late ManualMockBackendClient mockClient;
  late PostRepository repo;

  setUp(() {
    mockClient = ManualMockBackendClient();
    BackendService.instance = mockClient;
    repo = PostRepository();
  });

  group('PostRepository', () {
    test('createPost calls BackendService and returns ID', () async {
      final id = await repo.createPost(
        title: 'New Post',
        body: 'Content',
        category: 'General',
      );

      expect(id, "mock_id");
      expect(mockClient.lastData!['title'], 'New Post');
    });

    test('deletePost calls BackendService', () async {
      await repo.deletePost('post_123');
      expect(mockClient.lastId, 'post_123');
    });

    test('getPostsPaginated parses response correctly', () async {
      final mockData = [
        {
          'id': 'p1',
          'authorId': 'u1',
          'authorName': 'User 1',
          'title': 'Post 1',
          'body': 'Body 1',
          'createdAt': '2024-02-21T10:00:00Z',
          'likeCount': 5,
          'commentCount': 2,
          'isEvent': false,
          'attendeeCount': 0,
        }
      ];

      mockClient.mockResponse = ApiResponse.success(
        mockData,
        pagination: ApiResponsePagination(cursor: 'p1', hasMore: true),
      );

      final response = await repo.getPostsPaginated(feedType: 'discovery');

      expect(response.data.length, 1);
      expect(response.data.first.id, 'p1');
      expect(response.nextCursor, 'p1');
      expect(response.hasMore, true);
    });
  });
}
