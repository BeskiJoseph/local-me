import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../core/utils/time_utils.dart';
import '../../core/utils/navigation_utils.dart';
import '../../shared/widgets/user_avatar.dart';

class PostHeader extends StatelessWidget {
  final Post post;

  const PostHeader({super.key, required this.post});

  void _navigateToUserProfile(BuildContext context) {
    NavigationUtils.navigateToProfile(context, post.authorId);
  }

  String _formatTimeAgo(DateTime timestamp) => TimeUtils.formatTimeAgo(timestamp);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _navigateToUserProfile(context),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar with gradient border
            UserAvatar(
              imageUrl: post.authorProfileImage,
              name: post.authorName,
              radius: 22,
              showGradientBorder: true,
              initialsColor: Colors.white,
              backgroundColor: const Color(0xFF667EEA),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.authorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1C1C1E),
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTimeAgo(post.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: const Color(0xFF8E8E93),
              iconSize: 18,
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
