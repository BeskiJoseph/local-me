import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../screens/personal_account.dart';
import '../screens/post_detail_screen.dart';
import '../core/utils/time_utils.dart';
import '../shared/widgets/user_avatar.dart';

// ============================================================================
// NEXTDOOR-STYLE POST CARD
// ============================================================================

class NextdoorStylePostCard extends StatefulWidget {
  final Post post;
  final String? currentCity;

  const NextdoorStylePostCard({
    super.key,
    required this.post,
    this.currentCity,
  });

  @override
  State<NextdoorStylePostCard> createState() => _NextdoorStylePostCardState();
}

class _NextdoorStylePostCardState extends State<NextdoorStylePostCard> {
  // Optimistic state overrides
  bool? _optimisticLiked;
  int? _optimisticLikeCount;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = AuthService.currentUser;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (user != null && post.authorId != user.uid) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalAccount(
                          userId: post.authorId,
                        ),
                      ),
                    );
                  }
                },
                child: UserAvatar(
                  imageUrl: post.authorProfileImage,
                  name: post.authorName,
                  radius: 22,
                  backgroundColor: const Color(0xFFF0F0F0),
                  initialsColor: Colors.black54,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          post.authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            fontFamily: 'Inter',
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (post.authorId == 'official_account_id') // Example verification
                          const Icon(Icons.verified, size: 14, color: Color(0xFF2563EB)),
                        const Spacer(),
                        Text(
                          TimeUtils.formatTimeAgoCompact(post.createdAt),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.more_horiz, color: Colors.grey.shade400, size: 20),
                      ],
                    ),
                    if (post.city != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 2),
                            Text(
                              post.city!,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 10),
          
          // Content
          Padding(
            padding: const EdgeInsets.only(left: 0), // Full width title or body
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Inter',
                        color: Colors.black,
                      ),
                    ),
                  ),
                Text(
                  post.body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Color(0xFF262626),
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          
          // Media
          if (post.mediaUrl != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetailScreen(post: post),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1.1, // Feed optimized aspect ratio
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        ProxyHelper.getUrl(post.thumbnailUrl ?? post.mediaUrl!),
                        fit: BoxFit.cover,
                        cacheWidth: 800, // Optimize memory usage
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(color: Colors.grey.shade100);
                        },
                      ),
                      if (post.mediaType == 'video')
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 14),
          
          // Actions
          StreamBuilder<bool>(
            stream: user != null
                ? FirestoreService.isPostLikedStream(post.id, user.uid)
                : Stream.value(false),
            builder: (context, snapshot) {
              final streamLiked = snapshot.data ?? false;
              final isLiked = _optimisticLiked ?? streamLiked;
              final displayLikeCount = _optimisticLikeCount ?? post.likeCount;
              
              return Row(
                children: [
                  _buildActionButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    count: displayLikeCount,
                    isActive: isLiked,
                    activeColor: Colors.red,
                    onTap: () async {
                      if (user != null) {
                        final bool currentLiked = _optimisticLiked ?? streamLiked;
                        final bool newTarget = !currentLiked;
                        
                        setState(() {
                          _optimisticLiked = newTarget;
                          _optimisticLikeCount = newTarget 
                              ? (_optimisticLikeCount ?? post.likeCount) + 1 
                              : (_optimisticLikeCount ?? post.likeCount) - 1;
                          if (_optimisticLikeCount! < 0) _optimisticLikeCount = 0;
                        });

                        try {
                          await BackendService.toggleLike(post.id);
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
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.chat_bubble_outline,
                    count: post.commentCount,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PostDetailScreen(post: post),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.repeat, // Repost style
                    onTap: () {},
                  ),
                  const Spacer(),
                  Icon(Icons.bookmark_border, color: Colors.grey.shade400, size: 22),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    int? count,
    bool isActive = false,
    Color activeColor = const Color(0xFF00B87C),
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? activeColor : Colors.black87,
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Text(
                count.toString(),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
