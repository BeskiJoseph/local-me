import '../models/user_profile.dart';
import '../models/signup_data.dart';
import '../services/backend_service.dart';

/// Repository for handling User Profile operations.
class UserRepository {
  UserRepository();

  // In-memory profile cache: uid → {data, fetchedAt}
  static final Map<String, Map<String, dynamic>> _profileCache = {};
  static const _cacheDuration = Duration(minutes: 5);

  static bool _isCacheValid(String uid) {
    final entry = _profileCache[uid];
    if (entry == null) return false;
    final age = DateTime.now().difference(entry['fetchedAt'] as DateTime);
    return age < _cacheDuration;
  }

  /// Returns a one-shot stream that emits the profile once and completes.
  Stream<UserProfile?> userProfileStream(String userId) async* {
    final initial = await getUserProfile(userId);
    yield initial;

    await for (final _ in Stream.periodic(const Duration(minutes: 5))) {
      invalidateCache(userId);
      yield await getUserProfile(userId);
    }
  }

  static Future<Map<String, dynamic>?> getCachedProfile(String uid) async {
    if (_isCacheValid(uid)) {
      return _profileCache[uid]!['data'] as Map<String, dynamic>?;
    }
    final response = await BackendService.getProfile(uid);
    if (response.success) {
      final data = response.data!;
      _profileCache[uid] = {'data': data, 'fetchedAt': DateTime.now()};
      return data;
    }
    return null;
  }

  static void invalidateCache(String uid) => _profileCache.remove(uid);

  Future<UserProfile?> getUserProfile(String userId) async {
    final data = await getCachedProfile(userId);
    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  Future<void> createUserProfile({
    required String uid,
    required String? displayName,
    required String? photoURL,
    required SignupData data,
    String? profileImageUrl,
  }) async {
    final response = await BackendService.updateProfile({
      'username': data.username ?? displayName ?? '',
      'firstName': data.firstName,
      'lastName': data.lastName,
      'profileImageUrl': profileImageUrl ?? photoURL,
    });
    if (!response.success) throw response.error ?? "Failed to create profile";
  }

  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? about,
    String? profileImageUrl,
    String? location,
  }) async {
    final response = await BackendService.updateProfile({
      if (displayName != null) 'username': displayName,
      if (about != null) 'about': about,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      if (location != null) 'location': location,
    });
    if (!response.success) throw response.error ?? "Update failed";
    invalidateCache(userId);
  }

  Future<void> syncGoogleUser(String uid) async {
    invalidateCache(uid);
    await getCachedProfile(uid);
  }
}
