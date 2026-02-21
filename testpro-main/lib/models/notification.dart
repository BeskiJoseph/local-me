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

  factory ActivityNotification.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      if (date is DateTime) return date;
      return DateTime.tryParse(date.toString()) ?? DateTime.now();
    }

    return ActivityNotification(
      id: json['id'] as String? ?? '',
      fromUserId: json['fromUserId'] as String? ?? '',
      fromUserName: json['fromUserName'] as String? ?? '',
      fromUserProfileImage: json['fromUserProfileImage'] as String?,
      toUserId: json['toUserId'] as String? ?? '',
      type: _parseType(json['type'] as String?),
      postId: json['postId'] as String?,
      postThumbnail: json['postThumbnail'] as String?,
      commentText: json['commentText'] as String?,
      timestamp: parseDate(json['timestamp']),
      isRead: json['isRead'] as bool? ?? false,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'fromUserProfileImage': fromUserProfileImage,
      'toUserId': toUserId,
      'type': type.name,
      'postId': postId,
      'postThumbnail': postThumbnail,
      'commentText': commentText,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }
}
