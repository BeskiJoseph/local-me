import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType {
  like,
  comment,
  follow,
  mention,
}

class ActivityNotification {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String? fromUserProfileImage;
  final String toUserId;
  final NotificationType type;
  final String? postId;
  final String? postThumbnail;
  final String? commentText;
  final DateTime timestamp;
  final bool isRead;

  ActivityNotification({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    this.fromUserProfileImage,
    required this.toUserId,
    required this.type,
    this.postId,
    this.postThumbnail,
    this.commentText,
    required this.timestamp,
    this.isRead = false,
  });

  factory ActivityNotification.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ActivityNotification(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? '',
      fromUserProfileImage: data['fromUserProfileImage'],
      toUserId: data['toUserId'] ?? '',
      type: _parseType(data['type']),
      postId: data['postId'],
      postThumbnail: data['postThumbnail'],
      commentText: data['commentText'],
      timestamp: data['timestamp'] != null 
          ? (data['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  static NotificationType _parseType(String? type) {
    switch (type) {
      case 'like':
        return NotificationType.like;
      case 'comment':
        return NotificationType.comment;
      case 'follow':
        return NotificationType.follow;
      case 'mention':
        return NotificationType.mention;
      default:
        return NotificationType.like;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'fromUserProfileImage': fromUserProfileImage,
      'toUserId': toUserId,
      'type': type.name,
      'postId': postId,
      'postThumbnail': postThumbnail,
      'commentText': commentText,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
    };
  }
}
