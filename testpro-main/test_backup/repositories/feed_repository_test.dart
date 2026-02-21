import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/feed_repository.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/models/api_response.dart';

class ManualMockBackendClient extends BackendClient {
  ApiResponse? mockResponse;

  @override
  Future<ApiResponse<List<dynamic>>> getFeed({String? cursor, int limit = 10, String type = 'discovery'}) async {
    return (mockResponse as ApiResponse<List<dynamic>>?) ?? ApiResponse.success([
      {
        'id': 'p1',
        'authorId': 'u1',
        'authorName': 'User 1',
        'title': 'Flutter Post',
        'body': 'Body 1',
        'createdAt': '2024-02-21T10:00:00Z',
        'likeCount': 0,
        'commentCount': 0,
        'isEvent': false,
        'attendeeCount': 0,
      }
    ]);
  }
}

void main() {
  late ManualMockBackendClient mockClient;
  late FeedRepository repo;

  setUp(() {
    mockClient = ManualMockBackendClient();
    BackendService.instance = mockClient;
    repo = FeedRepository();
  });

  group('FeedRepository', () {
    test('getRecommendedFeed calls BackendService and parses results', () async {
      final feed = await repo.getRecommendedFeed(userId: 'user1', limit: 10);
      
      expect(feed.length, 1);
      expect(feed.first.title, 'Flutter Post');
    });
  });
}
