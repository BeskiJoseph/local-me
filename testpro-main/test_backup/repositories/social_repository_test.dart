import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/social_repository.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/models/api_response.dart';

class ManualMockBackendClient extends BackendClient {
  ApiResponse? mockResponse;
  String? lastPostId;
  String? lastTargetId;

  @override
  Future<ApiResponse<bool>> toggleLike(String postId) async {
    lastPostId = postId;
    return (mockResponse as ApiResponse<bool>?) ?? ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> toggleFollow(String targetUserId) async {
    lastTargetId = targetUserId;
    return (mockResponse as ApiResponse<bool>?) ?? ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> checkLikeState(String postId) async {
    return ApiResponse.success({'liked': true});
  }

  @override
  Future<ApiResponse<bool>> checkFollowState(String targetUserId) async {
    return ApiResponse.success(true);
  }
}

void main() {
  late ManualMockBackendClient mockClient;
  late SocialRepository repo;

  setUp(() {
    mockClient = ManualMockBackendClient();
    BackendService.instance = mockClient;
    repo = SocialRepository();
  });

  group('SocialRepository', () {
    test('toggleLikePost calls BackendService', () async {
      await repo.toggleLikePost('p1', 'u1');
      expect(mockClient.lastPostId, 'p1');
    });

    test('toggleFollowUser calls BackendService', () async {
      await repo.toggleFollowUser('u2');
      expect(mockClient.lastTargetId, 'u2');
    });

    test('isPostLikedStream emits correct value', () async {
      final value = await repo.isPostLikedStream('p1', 'u1').first;
      expect(value, isTrue);
    });

    test('isUserFollowedStream emits correct value', () async {
      final value = await repo.isUserFollowedStream('u1', 'u2').first;
      expect(value, isTrue);
    });
  });
}
