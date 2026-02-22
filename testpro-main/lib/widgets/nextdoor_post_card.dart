import 'package:flutter/material.dart';
import '../models/post.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../screens/personal_account.dart';
import '../screens/post_detail_screen.dart';
import '../core/utils/time_utils.dart';
import '../shared/widgets/user_avatar.dart';

/// ============================================================
/// POST CARD — pixel-matched to screenshot
/// White background, flat (no card border/shadow).
/// Header → chip → body → media → reaction row → gray divider.
/// ============================================================
class NextdoorStylePostCard extends StatefulWidget {
  final Post post;
  final String? currentCity;
  final bool? initialIsLiked;

  const NextdoorStylePostCard({
    super.key,
    required this.post,
    this.currentCity,
    this.initialIsLiked,
  });

  @override
  State<NextdoorStylePostCard> createState() => _NextdoorStylePostCardState();
}

class _NextdoorStylePostCardState extends State<NextdoorStylePostCard> {
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLoadingLikeState = true;
  bool? _optimisticLiked;
  int? _optimisticLikeCount;
  bool _isTogglingLike = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _isLiked = widget.initialIsLiked ?? widget.post.isLiked;
    _isLoadingLikeState = false;
  }



  Future<void> _handleLike() async {
    if (_isTogglingLike) return;
    final user = AuthService.currentUser;
    if (user == null) return;

    _isTogglingLike = true;
    final currentLiked = _optimisticLiked ?? _isLiked;
    final newTarget = !currentLiked;
    final currentCount = _optimisticLikeCount ?? _likeCount;

    setState(() {
      _optimisticLiked = newTarget;
      _optimisticLikeCount = currentCount + (newTarget ? 1 : -1);
    });

    try {
      final response = await BackendService.toggleLike(widget.post.id);
      if (!response.success) throw response.error ?? "Toggle failed";
      // Refresh real state from backend after small delay to let backend sync
      final response2 = await BackendService.checkLikeState(widget.post.id);
      if (mounted && response2.success) {
        final data2 = response2.data!;
        setState(() {
          _isLiked = data2['liked'] ?? false;
          _likeCount = (data2['likeCount'] as num?)?.toInt() ?? widget.post.likeCount;
          _optimisticLiked = null;
          _optimisticLikeCount = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticLiked = null;
          _optimisticLikeCount = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTogglingLike = false);
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final response = await BackendService.deletePost(widget.post.id);
      if (response.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = AuthService.currentUser;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: _PostHeader(
              post: post,
              user: user,
              onDelete: _handleDelete,
            ),
          ),

          // ── Category & Text Content ───────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Category Chip ────────────────────────────────
                if (post.category.isNotEmpty) ...[
                  _CategoryChip(label: post.category.toUpperCase()),
                  const SizedBox(height: 12),
                ],

                // ── Title ────────────────────────────────────────
                if (post.title.isNotEmpty) ...[
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Body (Optional fallback) ─────────────────────
                if (post.body.isNotEmpty && post.body != post.title) ...[
                  Text(
                    post.body,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      color: Color(0xFF333333),
                      height: 1.5,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),

          // ── Media ────────────────────────────────────────────
          if (post.mediaUrl != null) ...[
            _PostMedia(post: post),
            const SizedBox(height: 6),
          ],

          // ── Reaction Row ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: _ReactionRow(
              post: post,
              isLiked: _optimisticLiked ?? _isLiked,
              likeCount: _optimisticLikeCount ?? _likeCount,
              onLike: user != null ? _handleLike : null,
              onComment: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PostDetailScreen(post: post)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header: avatar | name + location | time | ···
// ─────────────────────────────────────────────────────────────
class _PostHeader extends StatelessWidget {
  final Post post;
  final dynamic user;
  final VoidCallback? onDelete;

  const _PostHeader({required this.post, this.user, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar
        GestureDetector(
          onTap: () {
            if (user != null && post.authorId != user.uid) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PersonalAccount(userId: post.authorId)),
              );
            }
          },
          child: UserAvatar(
            imageUrl: post.authorProfileImage,
            name: post.authorName,
            radius: 22,
            backgroundColor: AppTheme.primaryLight,
            initialsColor: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),

        // Name + location
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (post.authorName.isEmpty || post.authorName == 'User') 
                    ? (user?.uid == post.authorId 
                        ? (user?.displayName ?? user?.email?.split('@')[0] ?? 'User')
                        : 'User')
                    : post.authorName,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              if (post.city != null && post.city!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 13, color: Color(0xFF8A8A8A)),
                    const SizedBox(width: 2),
                    Text(
                      post.city!,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Time
        Text(
          TimeUtils.formatTimeAgoCompact(post.createdAt),
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 13,
            color: Color(0xFF8A8A8A),
          ),
        ),
        const SizedBox(width: 8),

        // 3-dot menu
        GestureDetector(
          onTap: () => _showOptions(context),
          child: const Icon(Icons.more_horiz,
              color: Color(0xFF8A8A8A), size: 22),
        ),
      ],
    );
  }

  void _showOptions(BuildContext context) {
    final isOwner = user != null && post.authorId == user.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionsSheet(
        isOwner: isOwner,
        post: post,
        onDelete: onDelete,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary, // #2F7D6A
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          fontFamily: AppTheme.fontFamily,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Media — full width, 16:10 ratio, rounded corners, video badge
// ─────────────────────────────────────────────────────────────
class _PostMedia extends StatelessWidget {
  final Post post;
  const _PostMedia({required this.post});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  ProxyHelper.getUrl(
                      post.thumbnailUrl ?? post.mediaUrl!),
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(color: const Color(0xFFECECEC));
                  },
                  errorBuilder: (context, error, stack) => Container(
                    color: const Color(0xFFECECEC),
                    child: const Icon(Icons.broken_image_outlined,
                        color: Color(0xFF8A8A8A)),
                  ),
                ),
                // Video duration badge
                if (post.mediaType == 'video')
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reaction Row: ♡ 256  💬 23  • 5.4k views  [bookmark]
// ─────────────────────────────────────────────────────────────
class _ReactionRow extends StatelessWidget {
  final Post post;
  final bool isLiked;
  final int likeCount;
  final VoidCallback? onLike;
  final VoidCallback onComment;

  const _ReactionRow({
    required this.post,
    required this.isLiked,
    required this.likeCount,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Like
        _ActionBtn(
          icon: isLiked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          label: likeCount > 0 ? _fmt(likeCount) : '0',
          color: isLiked
              ? const Color(0xFFE53935)
              : const Color(0xFF6E6E73),
          onTap: onLike,
        ),
        const SizedBox(width: 8),

        // Comment
        _ActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: post.commentCount > 0 ? '${post.commentCount}' : '0',
          color: const Color(0xFF6E6E73),
          onTap: onComment,
        ),

        // Engagement info — events show attendee count, posts show nothing
        // (real view tracking to be implemented later)
        if (post.isEvent && post.attendeeCount > 0) ...[
          const SizedBox(width: 12),
          const Text('•',
              style: TextStyle(
                  color: Color(0xFF8A8A8A),
                  fontSize: 14,
                  fontFamily: AppTheme.fontFamily)),
          const SizedBox(width: 8),
          Text(
            '${_fmt(post.attendeeCount)} going',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              color: Color(0xFF6E6E73),
            ),
          ),
        ],

        const Spacer(),

        // Bookmark
        GestureDetector(
          onTap: () {},
          child: const Icon(Icons.bookmark_border_rounded,
              color: Color(0xFF6E6E73), size: 22),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionBtn(
      {required this.icon,
      this.label,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          if (label != null) ...[
            const SizedBox(width: 5),
            Text(
              label!,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Post Options Bottom Sheet
// ─────────────────────────────────────────────────────────────
class _OptionsSheet extends StatelessWidget {
  final bool isOwner;
  final Post post;
  final VoidCallback? onDelete;

  const _OptionsSheet({required this.isOwner, required this.post, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      // Clean cream/off-white background matching screenshot
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Handle pill
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // ── Options List ─────────────────────────────────────
          if (isOwner) ...[
            _Tile(
              icon: Icons.edit_outlined,
              label: 'Edit Post',
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.share_outlined,
              label: 'Share Post',
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.bar_chart_outlined,
              label: 'View Insights',
              iconColor: const Color(0xFF2E7D6A), // Greenish from screenshot
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.delete_outline_rounded,
              label: 'Delete Post',
              labelColor: const Color(0xFFE53935),
              onTap: () {
                Navigator.pop(context);
                if (onDelete != null) onDelete!();
              },
              isLast: true,
            ),
          ] else ...[
            _Tile(
              icon: Icons.link_rounded,
              label: 'Share Post',
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.bookmark_border_rounded,
              label: 'Bookmark',
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.notifications_off_outlined,
              label: 'Mute @${post.authorName.replaceAll(' ', '')}',
              labelColor: const Color(0xFFE53935), // reddish muted color
              iconColor: const Color(0xFF8A8A8A),
              onTap: () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.outlined_flag_rounded,
              label: 'Report Post',
              labelColor: const Color(0xFFE53935),
              onTap: () => Navigator.pop(context),
              isLast: true,
            ),
          ],

          // ── Cancel Button ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFECECEC),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF555555),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback onTap;
  final bool isLast;

  _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.iconColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = labelColor ?? const Color(0xFF1F1F1F);
    final iColor = iconColor ?? const Color(0xFF1F1F1F);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: iColor, size: 24),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 1, color: Color(0xFFF2F2F2)),
          ),
      ],
    );
  }
}
