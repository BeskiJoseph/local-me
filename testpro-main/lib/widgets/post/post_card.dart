import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../core/state/post_state.dart';
import '../../screens/post_reels_view.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../nextdoor_post_card.dart';

class PostCard extends ConsumerStatefulWidget {
  final String postId;
  final String? feedType;

  const PostCard({
    super.key,
    required this.postId,
    this.feedType,
  });


  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  @override
  Widget build(BuildContext context) {
    final post = ref.watch(postProvider(widget.postId));
    
    if (post == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    
    return VisibilityDetector(
      key: ValueKey('post_${widget.postId}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        final notifier = ref.read(postStoreProvider.notifier);
        
        // 🔥 MARK AS SEEN: > 60% visibility
        if (info.visibleFraction > 0.6) {
          notifier.markAsSeen(widget.postId);
          notifier.setVisible(widget.postId, true);
        } else if (info.visibleFraction <= 0.0) {
          notifier.setVisible(widget.postId, false);
        }
      },
      child: NextdoorStylePostCard(
        post: post,
        onTap: () {
          // ... existing tap logic ...
          // 🔥 FIX: Use feed-specific IDs if available to avoid mixing global/local in Reels
          final store = ref.read(postStoreProvider);
          final List<String> feedIds = widget.feedType != null
              ? (store.postIdsByFeedType[widget.feedType!] ?? [])
              : store.postIds;
          
          final allPosts = feedIds
              .map((id) => store.posts[id])
              .whereType<Post>()
              .toList();
              
          final index = allPosts.indexWhere((p) => p.id == post.id);


          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostReelsView(
                posts: allPosts,
                startIndex: index >= 0 ? index : 0,
                feedType: widget.feedType,
              ),

            ),
          );
        },
      ),
    );
  }
}
