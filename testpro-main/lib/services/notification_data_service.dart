import '../models/notification.dart';
import 'backend_service.dart';

class NotificationDataService {
  /// Polls every 5 minutes — notifications don't need near-real-time updates.
  /// Previous 15s polling was contributing to the request storm.
  static Stream<List<ActivityNotification>> notificationsStream(String userId) async* {
    yield await _fetch(userId);
    await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
      yield await _fetch(userId);
    }
  }

  static Future<List<ActivityNotification>> _fetch(String userId) async {
    final response = await BackendService.getNotifications();
    if (response.success) {
      return response.data!.map((json) => ActivityNotification.fromJson(json)).toList();
    }
    return [];
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    final response = await BackendService.markNotificationAsRead(notificationId);
    if (!response.success) throw response.error ?? "Failed to mark as read";
  }

  static Future<void> sendNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUserName,
    String? fromUserProfileImage,
    required NotificationType type,
    String? postId,
    String? postThumbnail,
    String? commentText,
  }) async {
    // Notifications are sent server-side — no client action needed.
  }
}
