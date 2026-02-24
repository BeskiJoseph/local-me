import 'package:flutter/foundation.dart';

class UserSessionData {
  final String uid;
  final String? displayName;
  final String? avatarUrl;

  UserSessionData({required this.uid, this.displayName, this.avatarUrl});
}

class UserSession {
  static final ValueNotifier<UserSessionData?> current = ValueNotifier(null);

  // Legacy getters to prevent breaking changes to edits already made
  static String? get uid => current.value?.uid;
  static String? get displayName => current.value?.displayName;
  static String? get avatarUrl => current.value?.avatarUrl;

  /// Updates the cached user session data.
  /// Call this on login, signup, and successful profile edits.
  static void update({
    required String? id,
    String? name,
    String? avatar,
  }) {
    if (id == null && current.value == null) return;
    
    final resolvedId = id ?? current.value!.uid;
    
    current.value = UserSessionData(
      uid: resolvedId,
      displayName: name ?? current.value?.displayName,
      avatarUrl: avatar ?? current.value?.avatarUrl,
    );
  }

  /// Clears the session on logout.
  static void clear() {
    current.value = null;
  }

  /// Checks if a given authorId matches the current authenticated user.
  static bool isMe(String authorId) {
    return current.value?.uid == authorId;
  }
}
