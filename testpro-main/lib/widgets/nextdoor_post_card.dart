import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/post_service.dart';
import '../utils/proxy_helper.dart';
import '../utils/safe_error.dart';

import '../screens/post_detail_screen.dart';
import '../screens/post_insights_screen.dart';
import '../core/utils/time_utils.dart';
import '../shared/widgets/user_avatar.dart';
import '../core/session/user_session.dart';
import '../core/utils/navigation_utils.dart';
import '../core/utils/haptic_service.dart';
import '../shared/widgets/heart_pop_overlay.dart';
import 'comments_bottom_sheet.dart';
import 'package:intl/intl.dart';
import 'dart:async';

/// ============================================================
/// POST CARD — pixel-matched to screenshot
/// White background, flat (no card border/shadow).
/// Header → chip → body → media → reaction row → gray divider.
/// ============================================================
class NextdoorStylePostCard extends StatefulWidget {
  final Post post;
  final String? currentCity;
  final bool? initialIsLiked;
  final VoidCallback? onTap;

  const NextdoorStylePostCard({
    super.key,
    required this.post,
    this.currentCity,
    this.initialIsLiked,
    this.onTap,
  });

  @override
  State<NextdoorStylePostCard> createState() => _NextdoorStylePostCardState();
}

class _NextdoorStylePostCardState extends State<NextdoorStylePostCard> {
  bool _isLiked = false;
  int _likeCount = 0;
  bool? _optimisticLiked;
  int? _optimisticLikeCount;
  bool _isTogglingLike = false;
  bool _isBookmarked = false;
  bool _bookmarkLoading = false;
  StreamSubscription? _eventSub;
  final List<Key> _activeHearts = [];

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _isLiked = widget.initialIsLiked ?? widget.post.isLiked;
    
    // Sync with global post events
    _eventSub = PostService.events.listen((event) {
      if (!mounted) return;
      if (event.type == FeedEventType.postLiked) {
        final data = event.data as Map<String, dynamic>;
        if (data['postId'] == widget.post.id) {
          setState(() {
            if (data['isLiked'] != null) _isLiked = data['isLiked'];
            _likeCount = data['likeCount'];
            // Reset optimistic states as they've been confirmed/synced
            _optimisticLiked = null;
            _optimisticLikeCount = null;
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(NextdoorStylePostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync from outside if we're NOT in the middle of a user interaction
    if (!_isTogglingLike && _optimisticLiked == null && _optimisticLikeCount == null) {
      final newLiked = widget.initialIsLiked ?? widget.post.isLiked;
      final newCount = widget.post.likeCount;
      if (newLiked != _isLiked || newCount != _likeCount) {
        setState(() {
          _isLiked = newLiked;
          _likeCount = newCount;
        });
      }
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }



  Future<void> _handleLike() async {
    if (_isTogglingLike) return;
    final user = AuthService.currentUser;
    if (user == null) return;

    _isTogglingLike = true;
    final currentLiked = _optimisticLiked ?? _isLiked;
    final newTarget = !currentLiked;
    final currentCount = _optimisticLikeCount ?? _likeCount;

    // Feedback
    if (newTarget) HapticService.medium();

    setState(() {
      _optimisticLiked = newTarget;
      _optimisticLikeCount = (currentCount + (newTarget ? 1 : -1)).clamp(0, 1 << 30);
    });

    try {
      final response = await BackendService.toggleLike(widget.post.id);
      if (!response.success) throw response.error ?? "Toggle failed";
      if (mounted) {
        setState(() {
          // Commit optimistic state instantly for smooth UX
          _isLiked = newTarget;
          _likeCount = _optimisticLikeCount ?? _likeCount;
          _optimisticLiked = null;
          _optimisticLikeCount = null;
        });
        // Emit global event for sync across feeds
        PostService.emit(FeedEvent(
          FeedEventType.postLiked, 
          {'postId': widget.post.id, 'isLiked': newTarget, 'likeCount': _likeCount}
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Roll back on failure
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
      try {
        await PostService.deletePost(widget.post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(safeErrorMessage(e))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = AuthService.currentUser;

    return GestureDetector(
      onTap: widget.onTap,
      child: ColoredBox(
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
                  Row(
                    children: [
                      _CategoryChip(label: post.category.toUpperCase()),
                      if (post.isEvent && post.computedStatus == 'archived') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Text(
                            'ARCHIVED',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Title ────────────────────────────────────────
                if (post.title.isNotEmpty) ...[
                  Text(
                    post.title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: post.computedStatus == 'archived' ? const Color(0xFF8A8A8A) : const Color(0xFF1A1A1A),
                      height: 1.3,
                      decoration: post.computedStatus == 'archived' ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Event Dates ──────────────────────────────────
                if (post.isEvent && post.eventStartDate != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: post.computedStatus == 'archived' ? const Color(0xFFC0C0C0) : AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatEventDateRange(post.eventStartDate!, post.eventEndDate),
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: post.computedStatus == 'archived' ? const Color(0xFF8A8A8A) : const Color(0xFF4A4A4A),
                          ),
                        ),
                      ),
                    ],
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
          // Show media section for posts with URLs or temporary posts
          if (post.mediaUrl != null || post.id.startsWith('temp_')) ...[
            _PostMedia(
              post: post, 
              activeHearts: _activeHearts,
              onDoubleTap: () {
                // If not already liked, like it
                if (!(_optimisticLiked ?? _isLiked)) {
                  _handleLike();
                }
                // Always show heart pop
                final heartKey = UniqueKey();
                setState(() => _activeHearts.add(heartKey));
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (mounted) setState(() => _activeHearts.remove(heartKey));
                });
              },
            ),
            const SizedBox(height: 6),
          ],

          // ── Reaction Row ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: _ReactionRow(
              post: post,
              isLiked: _optimisticLiked ?? _isLiked,
              likeCount: _optimisticLikeCount ?? _likeCount,
              isBookmarked: _isBookmarked,
              onLike: user != null ? _handleLike : null,
              onComment: () => CommentsBottomSheet.show(context, post),
              onBookmark: () {
                if (_bookmarkLoading) return; // Debounce rapid taps
                HapticService.light();
                final newState = !_isBookmarked;
                setState(() => _isBookmarked = newState);
                _bookmarkLoading = true;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(newState ? 'Post saved' : 'Post unsaved'),
                    duration: const Duration(milliseconds: 1500),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // Persist to backend (fire-and-forget with silent rollback)
                () async {
                  try {
                    final resp = newState
                        ? await BackendService.savePost(post.id)
                        : await BackendService.unsavePost(post.id);
                    if (!resp.success && mounted) {
                      setState(() => _isBookmarked = !newState);
                    }
                  } catch (_) {
                    if (mounted) setState(() => _isBookmarked = !newState);
                  } finally {
                    _bookmarkLoading = false;
                  }
                }();
              },
            ),
          ),
        ],
      ),
    ),
    );
  }

  String _formatEventDateRange(DateTime start, DateTime? end) {
    if (end == null) {
      return DateFormat('MMM d, yyyy • h:mm a').format(start);
    }
    
    final bool sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    
    if (sameDay) {
      // Oct 12, 5:00 PM - 8:00 PM
      final dateStr = DateFormat('MMM d, yyyy').format(start);
      final startStr = DateFormat('h:mm a').format(start);
      final endStr = DateFormat('h:mm a').format(end);
      return '$dateStr • $startStr - $endStr';
    } else {
      // Oct 12, 5 PM - Oct 14, 8 PM
      final startStr = DateFormat('MMM d, h:mm a').format(start);
      final endStr = DateFormat('MMM d, h:mm a').format(end);
      return '$startStr - $endStr';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Header: avatar | name + location | time | ···
// ─────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────
// Header: avatar | name + location | follow | time | ···
// ─────────────────────────────────────────────────────────────
class _PostHeader extends StatefulWidget {
  final Post post;
  final dynamic user;
  final VoidCallback? onDelete;

  const _PostHeader({required this.post, this.user, this.onDelete});

  @override
  State<_PostHeader> createState() => _PostHeaderState();
}

class _PostHeaderState extends State<_PostHeader> {
  bool _isFollowing = false;
  bool _isBusy = false;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.post.isFollowing;
    _subscription = PostService.events.listen((event) {
      if (event.type == FeedEventType.userFollowed) {
        final data = event.data as Map<String, dynamic>;
        if (data['userId'] == widget.post.authorId) {
          if (mounted) setState(() => _isFollowing = data['isFollowing']);
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }


  Future<void> _toggleFollow() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final newState = !_isFollowing;
    
    // Optimistic
    setState(() => _isFollowing = newState);
    PostService.emit(FeedEvent(FeedEventType.userFollowed, {'userId': widget.post.authorId, 'isFollowing': newState}));

    try {
      final res = await BackendService.toggleFollow(widget.post.authorId);
      if (!res.success && mounted) {
        // Rollback
        setState(() => _isFollowing = !newState);
        PostService.emit(FeedEvent(FeedEventType.userFollowed, {'userId': widget.post.authorId, 'isFollowing': !newState}));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isFollowing = !newState);
        PostService.emit(FeedEvent(FeedEventType.userFollowed, {'userId': widget.post.authorId, 'isFollowing': !newState}));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserSessionData?>(
      valueListenable: UserSession.current,
      builder: (context, sessionData, _) {
        final isMe = UserSession.isMe(widget.post.authorId);
        final displayAvatar = isMe ? (sessionData?.avatarUrl ?? widget.post.authorProfileImage) : widget.post.authorProfileImage;
        final displayName = isMe 
            ? (sessionData?.displayName ?? widget.post.authorName) 
            : ((widget.post.authorName.isEmpty || widget.post.authorName == 'User') ? 'User' : widget.post.authorName);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            GestureDetector(
              onTap: () {
                if (widget.user != null && widget.post.authorId != widget.user.uid) {
                  NavigationUtils.navigateToProfile(context, widget.post.authorId);
                }
              },
              child: UserAvatar(
                imageUrl: displayAvatar,
                name: displayName,
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
                    displayName,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (widget.post.city != null && widget.post.city!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFF8A8A8A)),
                        const SizedBox(width: 2),
                        Text(
                          widget.post.city!,
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

            // Follow Button (for others)
            if (!isMe && widget.user != null) ...[
              TextButton(
                onPressed: _toggleFollow,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _isFollowing ? 'Following' : 'Follow',
                  style: TextStyle(
                    color: _isFollowing ? const Color(0xFF8A8A8A) : AppTheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],

            // Time
            Text(
              TimeUtils.formatTimeAgoCompact(widget.post.createdAt),
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
              child: const Icon(Icons.more_horiz, color: Color(0xFF8A8A8A), size: 22),
            ),
          ],
        );
      },
    );
  }

  void _showOptions(BuildContext context) {
    final isOwner = widget.user != null && widget.post.authorId == widget.user.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _OptionsSheet(
        isOwner: isOwner,
        post: widget.post,
        onDelete: widget.onDelete,
        onEdit: () {
          Navigator.pop(context);
          // Navigate to edit screen (can be implemented later)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Edit feature coming soon')),
          );
        },
        onShare: () async {
          Navigator.pop(context);
          final shareText = '${widget.post.title.isNotEmpty ? widget.post.title : widget.post.body}\n\nShared via App';
          try {
            await Share.share(shareText);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(safeErrorMessage(e))),
              );
            }
          }
        },
        onViewInsights: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostInsightsScreen(post: widget.post)),
          );
        },
        onMute: () {
          Navigator.pop(context);
          _handleMuteUser(context);
        },
        onReport: () {
          Navigator.pop(context);
          _showReportDialog(context);
        },
      ),
    );
  }

  void _handleMuteUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mute @${widget.post.authorName}?'),
        content: Text(
          "You won't see posts from @${widget.post.authorName} in your feed anymore. You can unmute them from their profile.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Call mute user API
              try {
                final response = await BackendService.muteUser(widget.post.authorId);
                if (context.mounted) {
                  if (response.success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('@${widget.post.authorName} has been muted')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(safeErrorMessage(response.error))),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(safeErrorMessage(e))),
                  );
                }
              }
            },
            child: const Text('Mute', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    String? selectedReason;
    final reasons = [
      'Spam or misleading',
      'Harassment or hate speech',
      'Violence or dangerous content',
      'Nudity or sexual content',
      'False information',
      'Intellectual property violation',
      'Something else',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Report Post'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Why are you reporting this post?',
                  style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
                ),
                const SizedBox(height: 16),
                ...reasons.map((reason) => RadioListTile<String>(
                      title: Text(reason, style: const TextStyle(fontSize: 14)),
                      value: reason,
                      groupValue: selectedReason,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) {
                        setState(() => selectedReason = value);
                      },
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      // Call report post API
                      try {
                        final response = await BackendService.reportPost(widget.post.id, selectedReason!);
                        if (context.mounted) {
                          if (response.success) {
                            // Hide reported post from feed for this user
                            PostService.emit(FeedEvent(FeedEventType.postDeleted, widget.post.id));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Thank you for your report. Post hidden from your feed.'),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(safeErrorMessage(response.error))),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(safeErrorMessage(e))),
                          );
                        }
                      }
                    },
              child: const Text('Report', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
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
// Media — Instagram-style compact, 4:5 for images, 9:16 for video
// ─────────────────────────────────────────────────────────────
class _PostMedia extends StatelessWidget {
  final Post post;
  final List<Key> activeHearts;
  final VoidCallback onDoubleTap;

  const _PostMedia({
    required this.post, 
    required this.activeHearts,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = post.mediaType == 'video';
    final aspectRatio = isVideo ? 9 / 16 : 4 / 5;
    
    if (post.mediaUrl == null && post.id.startsWith('temp_')) {
      // ... (rest of loading state remains same)
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFECECEC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Uploading media...',
                    style: TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: ProxyHelper.getUrl(
                      post.thumbnailUrl ?? post.mediaUrl!),
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  placeholder: (context, url) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFEBEBF4),
                          Color(0xFFF7F7FA),
                          Color(0xFFEBEBF4),
                        ],
                        begin: Alignment(-1, 0),
                        end: Alignment(1, 0),
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Color(0xFFCCCCCC),
                        size: 32,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFFECECEC),
                    child: const Icon(Icons.broken_image_outlined,
                        color: Color(0xFF8A8A8A)),
                  ),
                ),
                // Dynamic Heart Pops
                ...activeHearts.map((key) => HeartPopOverlay(key: key)),
                
                // Video play badge
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
  final bool isBookmarked;
  final VoidCallback? onLike;
  final VoidCallback onComment;
  final VoidCallback? onBookmark;

  const _ReactionRow({
    required this.post,
    required this.isLiked,
    required this.likeCount,
    required this.isBookmarked,
    required this.onLike,
    required this.onComment,
    this.onBookmark,
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

        // Bookmark / Save
        _ActionBtn(
          icon: isBookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: isBookmarked
              ? AppTheme.primary
              : const Color(0xFF6E6E73),
          onTap: onBookmark,
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
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onViewInsights;
  final VoidCallback? onMute;
  final VoidCallback? onReport;

  const _OptionsSheet({
    required this.isOwner,
    required this.post,
    this.onDelete,
    this.onEdit,
    this.onShare,
    this.onViewInsights,
    this.onMute,
    this.onReport,
  });

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
              onTap: onEdit ?? () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.share_outlined,
              label: 'Share Post',
              onTap: onShare ?? () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.bar_chart_outlined,
              label: 'View Insights',
              iconColor: const Color(0xFF2E7D6A), // Greenish from screenshot
              onTap: onViewInsights ?? () => Navigator.pop(context),
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
              icon: Icons.share_outlined,
              label: 'Share Post',
              onTap: onShare ?? () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.visibility_off_outlined,
              label: 'Hide Post',
              onTap: () {
                Navigator.pop(context);
                // Persist hide to backend (fire-and-forget)
                BackendService.hidePost(post.id).then((_) {}).catchError((_) => null);
                PostService.emit(FeedEvent(FeedEventType.postDeleted, post.id));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Post hidden from your feed'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            _Tile(
              icon: Icons.notifications_off_outlined,
              label: 'Mute @${post.authorName.replaceAll(' ', '')}',
              iconColor: const Color(0xFF8A8A8A),
              onTap: onMute ?? () => Navigator.pop(context),
            ),
            _Tile(
              icon: Icons.outlined_flag_rounded,
              label: 'Report Post',
              labelColor: const Color(0xFFE53935),
              onTap: onReport ?? () => Navigator.pop(context),
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

  const _Tile({
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
