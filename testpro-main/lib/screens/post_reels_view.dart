import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

// New Architecture Imports
import 'package:testpro/core_feed/models/post.dart';
import 'package:testpro/core_feed/models/feed_type.dart';
import 'package:testpro/core_feed/controllers/feed_controller.dart'; // ✅ To get FeedState
import 'package:testpro/core_feed/store/post_store.dart';
import 'package:testpro/core_feed/controllers/reels_controller.dart';
import 'package:testpro/core_feed/services/post_interaction_service.dart';
import 'package:testpro/core_feed/utils/media_utility.dart';

import 'package:testpro/config/app_theme.dart';
import 'package:testpro/shared/widgets/user_avatar.dart';
import 'package:testpro/shared/widgets/heart_pop_overlay.dart';
import 'package:testpro/shared/widgets/expandable_text.dart';
import 'package:testpro/widgets/comments_bottom_sheet.dart';
import 'package:testpro/core/utils/haptic_service.dart';
import 'package:testpro/core/utils/navigation_utils.dart';

class PostReelsView extends StatefulWidget {
  final List<Post> posts;
  final int startIndex;
  final String? postId;
  final String? feedType; // 'local' or 'global'
  final String? authorId;

  const PostReelsView({
    super.key,
    this.posts = const [],
    this.startIndex = 0,
    this.postId,
    this.feedType = 'local',
    this.authorId,
  });

  @override
  State<PostReelsView> createState() => _PostReelsViewState();
}

class _PostReelsViewState extends State<PostReelsView> {
  late PageController _horizontalController;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.feedType == 'global' ? 1 : 0;
    _horizontalController = PageController(initialPage: _activeTabIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProfileMode = widget.authorId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (isProfileMode)
            ReelsVerticalFeed(
              controllerProvider: authorReelsControllerProvider(widget.authorId!),
              startIndex: widget.startIndex,
            )
          else
            PageView(
              controller: _horizontalController,
              onPageChanged: (i) => setState(() => _activeTabIndex = i),
              children: [
                ReelsVerticalFeed(
                  controllerProvider: nearbyReelsControllerProvider,
                  startIndex: _activeTabIndex == 0 ? widget.startIndex : 0,
                  isActiveTab: _activeTabIndex == 0,
                ),
                ReelsVerticalFeed(
                  controllerProvider: globalReelsControllerProvider,
                  startIndex: _activeTabIndex == 1 ? widget.startIndex : 0,
                  isActiveTab: _activeTabIndex == 1,
                ),
              ],
            ),

          // Top Header (Back Button, Tabs)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (!isProfileMode) ...[
                    const SizedBox(width: 8),
                    _TabButton(
                      label: 'Nearby',
                      isActive: _activeTabIndex == 0,
                      onTap: () => _horizontalController.animateToPage(0, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                    ),
                    const SizedBox(width: 24),
                    _TabButton(
                      label: 'Global',
                      isActive: _activeTabIndex == 1,
                      onTap: () => _horizontalController.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 17, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: isActive ? Colors.white : Colors.white60)),
          const SizedBox(height: 4),
          AnimatedContainer(duration: const Duration(milliseconds: 200), height: 2, width: isActive ? 24 : 0, color: Colors.white),
        ],
      ),
    );
  }
}

class ReelsVerticalFeed extends ConsumerStatefulWidget {
  final StateNotifierProvider<ReelsController, FeedState> controllerProvider;
  final int startIndex;
  final bool isActiveTab;

  const ReelsVerticalFeed({
    super.key,
    required this.controllerProvider,
    this.startIndex = 0,
    this.isActiveTab = true,
  });

  @override
  ConsumerState<ReelsVerticalFeed> createState() => _ReelsVerticalFeedState();
}

class _ReelsVerticalFeedState extends ConsumerState<ReelsVerticalFeed> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.startIndex);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(widget.controllerProvider.notifier).loadInitialReels();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(widget.controllerProvider);
    
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: state.postIds.length + (state.hasMore ? 1 : 0),
      onPageChanged: (index) {
        if (index >= state.postIds.length - 2) {
          ref.read(widget.controllerProvider.notifier).loadMore();
        }
      },
      itemBuilder: (context, index) {
        if (index == state.postIds.length) {
          return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
        }
        final postId = state.postIds[index];
        return ReelPostItem(
          key: ValueKey(postId),
          postId: postId,
          isCurrentPage: widget.isActiveTab,
        );
      },
    );
  }
}

class ReelPostItem extends ConsumerStatefulWidget {
  final String postId;
  final bool isCurrentPage;

  const ReelPostItem({super.key, required this.postId, required this.isCurrentPage});

  @override
  ConsumerState<ReelPostItem> createState() => _ReelPostItemState();
}

class _ReelPostItemState extends ConsumerState<ReelPostItem> {
  VideoPlayerController? _videoController;
  bool _isInitialized = false;
  final List<Key> _activeHearts = [];

  @override
  void didUpdateWidget(ReelPostItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentPage && !oldWidget.isCurrentPage) {
      _videoController?.play();
    } else if (!widget.isCurrentPage && oldWidget.isCurrentPage) {
      _videoController?.pause();
    }
  }

  void _initializeMedia(String? url) {
    if (url == null || _isInitialized) return;
    
    final proxiedUrl = MediaUtility.getProxyUrl(url);
    _videoController = VideoPlayerController.networkUrl(Uri.parse(proxiedUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        if (widget.isCurrentPage) _videoController?.play();
        _videoController?.setLooping(true);
      });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🧠 SSOT Connection: Watch this specific post
    final post = ref.watch(individualPostProvider(widget.postId));
    if (post == null) return const SizedBox.shrink();

    // Auto-init media once post data exists
    if (post.mediaUrl != null) _initializeMedia(post.mediaUrl);

    final interactionService = ref.read(postInteractionProvider);

    return VisibilityDetector(
      key: ValueKey('reel_${post.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.8 && mounted) {
           _videoController?.play();
        } else if (info.visibleFraction < 0.1 && mounted) {
           _videoController?.pause();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Video
          GestureDetector(
            onDoubleTap: () {
              if (!post.isLiked) interactionService.toggleLike(post.id);
              final heartKey = UniqueKey();
              setState(() => _activeHearts.add(heartKey));
              Future.delayed(const Duration(milliseconds: 800), () => setState(() => _activeHearts.remove(heartKey)));
            },
            onTap: () => _videoController?.value.isPlaying ?? false ? _videoController?.pause() : _videoController?.play(),
            child: _videoController != null && _isInitialized 
              ? SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _videoController!.value.size.width, height: _videoController!.value.size.height, child: VideoPlayer(_videoController!))))
              : const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1)),
          ),

          // Gradient Overlay
          IgnorePointer(
            child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x4D000000), Colors.transparent, Color(0xCC000000)], stops: [0.0, 0.4, 1.0]))),
          ),
          ..._activeHearts.map((k) => HeartPopOverlay(key: k)),

          // Actions
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              children: [
                _ActionButton(icon: post.isLiked ? Icons.favorite : Icons.favorite_border, color: post.isLiked ? Colors.red : Colors.white, label: '${post.likeCount}', onTap: () => interactionService.toggleLike(post.id)),
                const SizedBox(height: 20),
                _ActionButton(icon: Icons.chat_bubble_outline, color: Colors.white, label: '${post.commentCount}', onTap: () => CommentsBottomSheet.show(context, post)),
                const SizedBox(height: 20),
                _ActionButton(icon: Icons.send_outlined, color: Colors.white, label: '', onTap: () {}),
              ],
            ),
          ),

          // Author Info
          Positioned(
            bottom: 70,
            left: 12,
            right: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    UserAvatar(imageUrl: post.authorProfileImage ?? '', name: post.authorName, radius: 18),
                    const SizedBox(width: 10),
                    Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(post.title ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                if (post.body != null) Text(post.body!, style: const TextStyle(fontSize: 14, color: Colors.white70), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
