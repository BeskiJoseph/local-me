import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/notification.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../config/app_theme.dart';
import 'post_detail_screen.dart';
import '../shared/widgets/user_avatar.dart';
import '../shared/widgets/empty_state.dart';
import '../services/notification_data_service.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  final String _currentUserId = AuthService.currentUser?.uid ?? '';
  late TabController _tabController;
  
  List<ActivityNotification> _notifications = [];
  bool _isLoading = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNotifications(refresh: true);
  }

  Future<void> _loadNotifications({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) setState(() { _isLoading = true; _notifications.clear(); });

    try {
      final items = await NotificationDataService.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _isLoading = false;
        _hasMore = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    // Optimistic — mark all unread locally first
    setState(() {
      _notifications = _notifications.map((n) => ActivityNotification(
        id: n.id,
        fromUserId: n.fromUserId,
        fromUserName: n.fromUserName,
        fromUserProfileImage: n.fromUserProfileImage,
        toUserId: n.toUserId,
        type: n.type,
        postId: n.postId,
        postThumbnail: n.postThumbnail,
        commentText: n.commentText,
        timestamp: n.timestamp,
        isRead: true,
      )).toList();
    });

    try {
      await NotificationDataService.markAllAsRead(); // also resets ValueNotifier badge
    } catch (e) {
      if (kDebugMode) debugPrint('Error marking all as read: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.cardWhite,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Notification Central',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: 26),
              ),
              // Dynamic badge from local state
              Builder(
                builder: (context) {
                  final unreadCount = _notifications.where((n) => !n.isRead).length;
                  if (unreadCount == 0) return const SizedBox.shrink();
                  return Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppTheme.badgeRed,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab Row ──────────────────────────────────────────
          Container(
            color: AppTheme.cardWhite,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                _PillTab(
                  label: 'All',
                  isSelected: _tabController.index == 0,
                  onTap: () => setState(() => _tabController.index = 0),
                ),
                const SizedBox(width: 8),
                _PillTab(
                  label: 'Mentions',
                  isSelected: _tabController.index == 1,
                  onTap: () => setState(() => _tabController.index = 1),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _markAllAsRead,
                  child: const Text(
                    'Mark all as read',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),

          // ── Notification List ─────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadNotifications(refresh: true),
              color: AppTheme.primary,
              child: _buildNotificationList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    if (_isLoading && _notifications.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    
    final filteredNotifications = _notifications.where((n) {
      if (_tabController.index == 1) {
        return n.type == NotificationType.mention;
      }
      return true;
    }).toList();

    if (filteredNotifications.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.notifications_none_rounded,
        title: 'No activity yet',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: filteredNotifications.length,
      itemBuilder: (context, index) {
        // Simple section header logic
        if (index == 5 && filteredNotifications.length > 5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Earlier',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              _NotificationTile(
                notification: filteredNotifications[index],
                onTap: () => _handleNotificationTap(filteredNotifications[index]),
              ),
            ],
          );
        }
        return _NotificationTile(
          notification: filteredNotifications[index],
          onTap: () => _handleNotificationTap(filteredNotifications[index]),
        );
      },
    );
  }

  Future<void> _handleNotificationTap(ActivityNotification notification) async {
    if (!notification.isRead) {
      // Optimistic update
      setState(() {
        final idx = _notifications.indexWhere((n) => n.id == notification.id);
        if (idx != -1) {
          _notifications[idx] = ActivityNotification(
            id: notification.id,
            fromUserId: notification.fromUserId,
            fromUserName: notification.fromUserName,
            fromUserProfileImage: notification.fromUserProfileImage,
            toUserId: notification.toUserId,
            type: notification.type,
            postId: notification.postId,
            postThumbnail: notification.postThumbnail,
            commentText: notification.commentText,
            timestamp: notification.timestamp,
            isRead: true,
          );
        }
      });
      
      try {
        await BackendService.markNotificationAsRead(notification.id);
      } catch (e) {
        if (kDebugMode) debugPrint('Error marking notification as read: $e');
      }
    }

    if (!mounted) return;
    
    if (notification.postId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: notification.postId!)),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Pill Tab
// ─────────────────────────────────────────────────────────────
class _PillTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PillTab({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.durationFast,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          borderRadius: BorderRadius.circular(AppTheme.radiusCircle),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Notification Tile
// ─────────────────────────────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  final ActivityNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: notification.isRead ? Colors.transparent : AppTheme.primaryLight.withValues(alpha: 0.4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              imageUrl: notification.fromUserProfileImage,
              name: notification.fromUserName,
              radius: 22,
              backgroundColor: AppTheme.primaryLight,
              initialsColor: AppTheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: notification.fromUserName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' ${_getNotificationText(notification)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notification.timestamp),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.postThumbnail != null)
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(ProxyHelper.getUrl(notification.postThumbnail!)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
          ],
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
}
