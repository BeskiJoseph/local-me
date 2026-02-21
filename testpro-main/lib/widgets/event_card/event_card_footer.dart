import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/social_service.dart';
import '../../services/backend_service.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../screens/post_detail_screen.dart';
import '../../screens/personal_account.dart';

class EventCardFooter extends StatefulWidget {
  final Post post;

  const EventCardFooter({super.key, required this.post});

  @override
  State<EventCardFooter> createState() => _EventCardFooterState();
}

class _EventCardFooterState extends State<EventCardFooter> {
  bool? _optimisticLiked;
  int? _optimisticLikeCount;

  void _navigateToUserProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAccount(userId: widget.post.authorId),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    int? count,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive ? const Color(0xFFFF6B6B) : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              count != null ? '$count' : '',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFFFF6B6B) : Colors.grey.shade600,
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Organizer Info
          InkWell(
            onTap: _navigateToUserProfile,
            child: Row(
              children: [
                UserAvatar(
                  imageUrl: widget.post.authorProfileImage,
                  name: widget.post.authorName,
                  radius: 16,
                  backgroundColor: const Color(0xFFFF6B6B).withOpacity(0.2),
                  initialsColor: const Color(0xFFFF6B6B),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Organized by',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      (widget.post.authorName.isEmpty || widget.post.authorName == 'User')
                          ? (user?.uid == widget.post.authorId
                              ? (user?.displayName ?? user?.email?.split('@')[0] ?? 'User')
                              : 'User')
                          : widget.post.authorName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 24),

          // Interaction Row
          StreamBuilder<bool>(
            stream: user != null
                ? SocialService.isPostLikedStream(widget.post.id, user.uid)
                : Stream.value(false),
            builder: (context, snapshot) {
              final streamLiked = snapshot.data ?? false;
              final isLiked = _optimisticLiked ?? streamLiked;
              final displayLikeCount = _optimisticLikeCount ?? widget.post.likeCount;

              return Row(
                children: [
                  _buildActionButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    label: 'Useful',
                    count: displayLikeCount,
                    isActive: isLiked,
                    onTap: () async {
                      if (user != null) {
                        final bool currentLiked = _optimisticLiked ?? streamLiked;
                        final bool newTarget = !currentLiked;
                        
                        setState(() {
                          _optimisticLiked = newTarget;
                          _optimisticLikeCount = newTarget 
                              ? (_optimisticLikeCount ?? widget.post.likeCount) + 1 
                              : (_optimisticLikeCount ?? widget.post.likeCount) - 1;
                          if (_optimisticLikeCount! < 0) _optimisticLikeCount = 0;
                        });

                        try {
                          final response = await BackendService.toggleLike(widget.post.id);
                          if (!response.success) throw response.error ?? "Toggle failed";
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _optimisticLiked = null;
                              _optimisticLikeCount = null;
                            });
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 24),
                  _buildActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Reply',
                    count: widget.post.commentCount,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: widget.post),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
