import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../services/user_service.dart';
import '../services/notification_data_service.dart';
import '../services/feed_service.dart';

/// Repository for handling Social Interactions (Likes, Follows).
/// Accepts [FirebaseFirestore] for dependency injection.
class SocialRepository {
  final FirebaseFirestore _db;

  SocialRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  Future<void> toggleLikePost(String postId, String userId, {String? category, List<String>? tags}) async {
    final postRef = _db.collection('posts').doc(postId);
    final likeId = '${postId}_$userId';
    final likeRef = _db.collection('likes').doc(likeId);

    await _db.runTransaction((transaction) async {
      final likeDoc = await transaction.get(likeRef);
      final postDoc = await transaction.get(postRef);

      if (likeDoc.exists) {
        transaction.delete(likeRef);
        transaction.update(postRef, {'likeCount': FieldValue.increment(-1)});
      } else {
        transaction.set(likeRef, {
          'postId': postId,
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {'likeCount': FieldValue.increment(1)});
        
        // Send Notification (Side effect - masked in unit tests ideally)
        if (postDoc.exists) {
          final postData = postDoc.data() as Map<String, dynamic>;
          final authorId = postData['authorId'];
          if (authorId != userId) {
            try {
              final userProfile = await UserService.getUserProfile(userId);
              NotificationDataService.sendNotification(
                toUserId: authorId,
                fromUserId: userId,
                fromUserName: userProfile?.username ?? 'Someone',
                fromUserProfileImage: userProfile?.profileImageUrl,
                type: NotificationType.like,
                postId: postId,
                postThumbnail: postData['thumbnailUrl'] ?? postData['mediaUrl'],
              );
            } catch (e) {
              // Ignore notification errors in repository ops
            }
          }
        }

        // V3: Log behavioral signal
        if (category != null) {
          try {
            FeedService.logUserActivity(
              userId: userId,
              postId: postId,
              category: category,
              tags: tags ?? [],
              liked: true,
            );
          } catch (e) {
            // Ignore feed logging errors
          }
        }
      }
    }).catchError((e) {
      if (kDebugMode) print("Like Error: $e");
      throw "Action failed. Check your connection.";
    });
  }

  Future<void> setPostLike(String postId, String userId, bool shouldLike) async {
    final postRef = _db.collection('posts').doc(postId);
    final likeId = '${postId}_$userId';
    final likeRef = _db.collection('likes').doc(likeId);

    await _db.runTransaction((transaction) async {
      final likeDoc = await transaction.get(likeRef);
      final bool alreadyLiked = likeDoc.exists;

      if (shouldLike && !alreadyLiked) {
        transaction.set(likeRef, {
          'postId': postId,
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {'likeCount': FieldValue.increment(1)});
      } else if (!shouldLike && alreadyLiked) {
        transaction.delete(likeRef);
        transaction.update(postRef, {'likeCount': FieldValue.increment(-1)});
      }
    }).catchError((e) {
      if (kDebugMode) print("Set Like Error: $e");
      throw "Action Failed: ${e.toString()}";
    });
  }

  Stream<bool> isPostLikedStream(String postId, String userId) {
    final likeId = '${postId}_$userId';
    return _db
        .collection('likes')
        .doc(likeId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<void> followUser(String currentUserId, String targetUserId) async {
    final followingId = '${currentUserId}_$targetUserId';
    final followRef = _db.collection('follows').doc(followingId);
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final targetUserRef = _db.collection('users').doc(targetUserId);

    await _db.runTransaction((transaction) async {
      final followDoc = await transaction.get(followRef);
      if (followDoc.exists) return; // Already following

      transaction.set(followRef, {
        'followerId': currentUserId,
        'followingId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Update counts
      transaction.update(currentUserRef, {'followingCount': FieldValue.increment(1)});
      transaction.update(targetUserRef, {'subscribers': FieldValue.increment(1)});

      // Send Notification
      try {
        final userProfile = await UserService.getUserProfile(currentUserId);
        NotificationDataService.sendNotification(
          toUserId: targetUserId,
          fromUserId: currentUserId,
          fromUserName: userProfile?.username ?? 'Someone',
          fromUserProfileImage: userProfile?.profileImageUrl,
          type: NotificationType.follow,
        );
      } catch (e) {
        // Ignore
      }
    }).catchError((e, stack) {
      if (kDebugMode) print("Follow Error: $e");
      throw "Action Failed: ${e.toString()}";
    });
  }

  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    final followingId = '${currentUserId}_$targetUserId';
    final followRef = _db.collection('follows').doc(followingId);
    final currentUserRef = _db.collection('users').doc(currentUserId);
    final targetUserRef = _db.collection('users').doc(targetUserId);

    await _db.runTransaction((transaction) async {
      final followDoc = await transaction.get(followRef);
      if (!followDoc.exists) return; // Not following

      transaction.delete(followRef);
      // Update counts
      transaction.update(currentUserRef, {'followingCount': FieldValue.increment(-1)});
      transaction.update(targetUserRef, {'subscribers': FieldValue.increment(-1)});
    }).catchError((e, stack) {
      if (kDebugMode) print("Unfollow Error: $e");
      throw "Action Failed: ${e.toString()}";
    });
  }

  Stream<List<UserProfile>> followersStream(String userId) {
    return _db
        .collection('follows')
        .where('followingId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return [];
      final followerIds = snapshot.docs.map((doc) => doc.get('followerId') as String).toList();

      final profiles = <UserProfile>[];
      for (var id in followerIds) {
        final doc = await _db.collection('users').doc(id).get();
        if (doc.exists) {
          profiles.add(UserProfile.fromMap(doc.id, doc.data()!));
        }
      }
      return profiles;
    });
  }

  Stream<bool> isUserFollowedStream(String currentUserId, String targetUserId) {
    final followId = '${currentUserId}_$targetUserId';
    return _db
        .collection('follows')
        .doc(followId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Stream<List<Post>> likedPostsStream(String userId) {
    return _db.collection('likes')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .asyncMap((snapshot) async {
        final posts = <Post>[];
        for (var doc in snapshot.docs) {
          final postId = doc.get('postId') as String?;
          if (postId != null) {
            final postDoc = await _db.collection('posts').doc(postId).get();
            if (postDoc.exists) {
              posts.add(Post.fromFirestore(postDoc));
            }
          }
        }
        return posts;
      });
  }

  Stream<List<Post>> joinedEventsStream(String userId) {
    return _db.collection('event_attendance')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
          final posts = <Post>[];
          for (var doc in snapshot.docs) {
            final eventId = doc.get('eventId') as String?;
            if (eventId != null) {
              final eventDoc = await _db.collection('posts').doc(eventId).get();
              if (eventDoc.exists) {
                posts.add(Post.fromFirestore(eventDoc));
              }
            }
          }
          return posts;
        });
  }
}
