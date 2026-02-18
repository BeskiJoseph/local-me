import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/comment.dart';
import '../models/notification.dart';
import 'notification_data_service.dart';

class CommentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<List<Comment>> commentsStream(String postId) {
    final query = _db
        .collection('comments')
        .where('postId', isEqualTo: postId)
        .orderBy('createdAt', descending: true);

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Comment.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  static Future<void> addComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorProfileImage,
    required String text,
  }) async {
    final postRef = _db.collection('posts').doc(postId);
    final commentsRef = _db.collection('comments');

    await _db.runTransaction((transaction) async {
      final postDoc = await transaction.get(postRef);
      // Add comment
      final newCommentRef = commentsRef.doc();
      transaction.set(newCommentRef, {
        'postId': postId,
        'authorId': authorId,
        'authorName': authorName,
        'authorProfileImage': authorProfileImage,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Increment comment count
      transaction.update(postRef, {'commentCount': FieldValue.increment(1)});

      // Send Notification
      if (postDoc.exists) {
        final postData = postDoc.data() as Map<String, dynamic>;
        final postAuthorId = postData['authorId'];
        if (postAuthorId != authorId) {
          NotificationDataService.sendNotification(
            toUserId: postAuthorId,
            fromUserId: authorId,
            fromUserName: authorName,
            fromUserProfileImage: authorProfileImage,
            type: NotificationType.comment,
            postId: postId,
            postThumbnail: postData['thumbnailUrl'] ?? postData['mediaUrl'],
            commentText: text,
          );
        }
      }
    }).catchError((e) {
      if (kDebugMode) print("Add Comment Error: $e");
      throw "Permission Denied. Please Check your Firebase Console > Firestore rules are published.";
    });
  }
}
