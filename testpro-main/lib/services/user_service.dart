import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/signup_data.dart';
import '../repositories/user_repository.dart';

/// Facade for [UserRepository].
/// Provides static access to user-related operations while allowing
/// the underlying repository to be swapped for testing.
class UserService {
  static UserRepository _repository = UserRepository();
  
  static UserRepository get repository => _repository;
  
  // setter for testing
  static set repository(UserRepository repo) => _repository = repo;

  static Stream<UserProfile?> userProfileStream(String userId) {
    return _repository.userProfileStream(userId);
  }

  static Future<UserProfile?> getUserProfile(String userId) {
    return _repository.getUserProfile(userId);
  }

  static Future<void> createUserProfile({
    required User user,
    required SignupData data,
    String? profileImageUrl,
  }) {
    return _repository.createUserProfile(
      user: user,
      data: data,
      profileImageUrl: profileImageUrl,
    );
  }

  static Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? about,
    String? profileImageUrl,
  }) {
    return _repository.updateUserProfile(
      userId: userId,
      displayName: displayName,
      about: about,
      profileImageUrl: profileImageUrl,
    );
  }

  static Future<void> syncGoogleUser(User user) {
    return _repository.syncGoogleUser(user);
  }

  static Future<void> incrementContentCount(String userId) {
    return _repository.incrementContentCount(userId);
  }

  static Future<void> recalculateUserStats(String userId) {
    return _repository.recalculateUserStats(userId);
  }
}
