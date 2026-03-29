import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core_feed/models/post.dart';
import '../../core_feed/store/post_store.dart'; // ✅ To get postStoreProvider
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
    final post = ref.watch(individualPostProvider(widget.postId));
    
    if (post == null) {
      return const SizedBox.shrink();
    }
    
    return VisibilityDetector(
      key: ValueKey('post_${widget.postId}'),
      onVisibilityChanged: (info) {
        // ... (Optional) Visibility logic can be added here if needed for tracking
      },
      child: NextdoorStylePostCard(
        post: post,
        onTap: () {
          // Navigating to Reels
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostReelsView(
                posts: [post], // Minimal fallback or load from store
                startIndex: 0,
                feedType: widget.feedType,
              ),
            ),
          );
        },
      ),
    );
  }
}
