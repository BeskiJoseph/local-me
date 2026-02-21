import '../models/user_profile.dart';
import '../models/signup_data.dart';
import '../repositories/user_repository.dart';
import 'auth_service.dart';

/// Facade for [UserRepository].
class UserService {
  static UserRepository _repository = UserRepository();

  static UserRepository get repository => _repository;

  static set repository(UserRepository repo) => _repository = repo;

  static Stream<UserProfile?> userProfileStream(String userId) {
    return _repository.userProfileStream(userId);
  }

  static Future<UserProfile?> getUserProfile(String userId) {
    return _repository.getUserProfile(userId);
  }

  static Future<void> createUserProfile({
    required String uid,
    required String? displayName,
    required String? photoURL,
    required SignupData data,
    String? profileImageUrl,
  }) {
    return _repository.createUserProfile(
      uid: uid,
      displayName: displayName,
      photoURL: photoURL,
      data: data,
      profileImageUrl: profileImageUrl,
    );
  }

  static Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? about,
    String? profileImageUrl,
    String? location,
  }) async {
    // 1. Update Profile via Repository
    await _repository.updateUserProfile(
      userId: userId,
      displayName: displayName,
      about: about,
      profileImageUrl: profileImageUrl,
      location: location,
    );

    // 2. Sync with Firebase Auth
    if (displayName != null || profileImageUrl != null) {
      await AuthService.updateProfile(
        displayName: displayName,
        photoURL: profileImageUrl,
      );
    }
  }

  static Future<void> syncGoogleUser(String uid) {
    return _repository.syncGoogleUser(uid);
  }
}
