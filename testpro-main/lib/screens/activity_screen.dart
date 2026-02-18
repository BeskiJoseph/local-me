import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/notification.dart';
import '../services/firestore_service.dart';
import '../utils/proxy_helper.dart';
import 'post_detail_screen.dart';
import '../shared/widgets/user_avatar.dart';
import '../shared/widgets/empty_state.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Activity',
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Inter',
          ),
        ),
      ),
      body: StreamBuilder<List<ActivityNotification>>(
        stream: FirestoreService.notificationsStream(_currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.notifications_none,
              title: 'No activity yet',
            );
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              return _buildNotificationItem(notifications[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(ActivityNotification notification) {
    return InkWell(
      onTap: () => _handleNotificationTap(notification),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: notification.isRead ? Colors.white : Colors.blue.withOpacity(0.05),
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade100),
          ),
        ),
        child: Row(
          children: [
            _buildUserAvatar(notification),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: Colors.black,
                      ),
                      children: [
                        TextSpan(
                          text: notification.fromUserName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' ${_getNotificationText(notification)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notification.timestamp),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.postThumbnail != null)
              _buildPostThumbnail(notification),
          ],
        ),
      ),
    );
  }

  Widget _buildUserAvatar(ActivityNotification notification) {
    return UserAvatar(
      imageUrl: notification.fromUserProfileImage,
      name: notification.fromUserName,
      radius: 22,
      initialsColor: Colors.white,
    );
  }

  Widget _buildPostThumbnail(ActivityNotification notification) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        image: DecorationImage(
          image: NetworkImage(ProxyHelper.getUrl(notification.postThumbnail!)),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  String _getNotificationText(ActivityNotification notification) {
    switch (notification.type) {
      case NotificationType.like:
        return 'liked your post.';
      case NotificationType.comment:
        return 'commented: ${notification.commentText}';
      case NotificationType.follow:
        return 'started following you.';
      case NotificationType.mention:
        return 'mentioned you in a post.';
    }
  }

  void _handleNotificationTap(ActivityNotification notification) {
    // Mark as read
    if (!notification.isRead) {
      FirestoreService.markNotificationAsRead(notification.id);
    }

    // Navigate to post if applicable
    if (notification.postId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(postId: notification.postId!),
        ),
      );
    }
  }
}
