import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/signup_data.dart';
import 'package:testpro/repositories/user_repository.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/models/api_response.dart';

class ManualMockBackendClient extends BackendClient {
  ApiResponse? mockResponse;
  Map<String, dynamic>? lastUpdate;

  @override
  Future<ApiResponse<Map<String, dynamic>>> getProfile(String uid) async {
    return (mockResponse as ApiResponse<Map<String, dynamic>>?) ?? ApiResponse.success({
      'uid': uid,
      'username': 'mockuser',
      'email': 'mock@test.com',
    });
  }

  @override
  Future<ApiResponse<bool>> updateProfile(Map<String, dynamic> data) async {
    lastUpdate = data;
    return (mockResponse as ApiResponse<bool>?) ?? ApiResponse.success(true);
  }
}

void main() {
  late ManualMockBackendClient mockClient;
  late UserRepository repo;

  setUp(() {
    mockClient = ManualMockBackendClient();
    BackendService.instance = mockClient;
    repo = UserRepository();
  });

  group('UserRepository', () {
    test('createUserProfile calls BackendService', () async {
      final data = SignupData()
        ..username = 'testuser'
        ..firstName = 'Test'
        ..lastName = 'User';

      await repo.createUserProfile(uid: 'u1', displayName: 'D', photoURL: 'P', data: data);

      expect(mockClient.lastUpdate!['username'], 'testuser');
      expect(mockClient.lastUpdate!['firstName'], 'Test');
    });

    test('updateUserProfile calls BackendService and invalidates cache', () async {
      await repo.updateUserProfile(
        userId: 'u1',
        displayName: 'newName',
        about: 'newAbout',
      );

      expect(mockClient.lastUpdate!['username'], 'newName');
      expect(mockClient.lastUpdate!['about'], 'newAbout');
    });

    test('getUserProfile parses response correctly', () async {
      final profile = await repo.getUserProfile('u1');
      expect(profile!.username, 'mockuser');
      expect(profile.id, 'u1');
    });
  });
}
