import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/notification.dart';
import 'backend_service.dart';

class NotificationDataService {
  /// Global unread badge count — any widget can listen with ValueListenableBuilder.
  /// Incremented by FCM push (zero polling), reset when user reads all.
  static final ValueNotifier<int> unreadCount = ValueNotifier(0);

  /// Call once from main.dart after NotificationService.initialize().
  /// Hooks into FCM onMessage so badge increments instantly on push arrival.
  static void initialize() {
    FirebaseMessaging.onMessage.listen((message) {
      unreadCount.value += 1;
    });
  }

  /// Fetch full notification list from backend (called once on ActivityScreen open).
  static Future<List<ActivityNotification>> fetchNotifications() async {
    final response = await BackendService.getNotifications();
    if (response.success && response.data != null) {
      final items = response.data!
          .map((json) => ActivityNotification.fromJson(json))
          .toList();
      // Sync badge to actual unread count from server
      unreadCount.value = items.where((n) => !n.isRead).length;
      return items;
    }
    return [];
  }

  /// Mark a single notification as read, decrement badge.
  static Future<void> markNotificationAsRead(String notificationId) async {
    final response = await BackendService.markNotificationAsRead(notificationId);
    if (!response.success) throw response.error ?? 'Failed to mark as read';
    if (unreadCount.value > 0) unreadCount.value -= 1;
  }

  /// Mark all as read — resets badge to zero immediately.
  static Future<void> markAllAsRead() async {
    final response = await BackendService.markAllNotificationsAsRead();
    if (!response.success) throw response.error ?? 'Failed to mark all as read';
    unreadCount.value = 0;
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

