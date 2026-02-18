import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification.dart';

class NotificationDataService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<ActivityNotification>> notificationsStream(String userId) {
    return _db
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ActivityNotification.fromFirestore(doc))
          .toList();
    });
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({'isRead': true});
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
    try {
      if (toUserId == fromUserId) return; // Don't notify self
      
      await _db.collection('notifications').add({
        'toUserId': toUserId,
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'fromUserProfileImage': fromUserProfileImage,
        'type': type.name,
        'postId': postId,
        'postThumbnail': postThumbnail,
        'commentText': commentText,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }
}
