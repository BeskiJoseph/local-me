import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/post.dart';
import '../store/post_store.dart';
import '../services/post_interaction_service.dart';
import 'package:testpro/services/auth_service.dart'; // ✅ To check for OWN post
import '../utils/media_utility.dart'; 
import './post_video_player.dart'; // ✅ NEW: Video Player
import 'package:cached_network_image/cached_network_image.dart';

/// A pure, "dumb" renderer for a single Post.
/// Responsibility: Display data + trigger interaction callbacks.
class PostCard extends ConsumerWidget {
  final String postId;

  const PostCard({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 🧠 SSOT Connection: Watch the central store for this specific post
    final post = ref.watch(postStoreProvider.select((posts) => posts[postId]));
    
    // SAFE UI CHECK: If post is missing, show placeholder/empty
    if (post == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PostHeader(post: post),
          if (post.body != null && post.body!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                post.body!,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
          if (post.mediaUrl != null && post.mediaUrl!.isNotEmpty)
             _MediaContent(mediaUrl: post.mediaUrl!, mediaType: post.mediaType),
          _PostActionRow(post: post),
        ],
      ),
    );
  }
}

class _MediaContent extends StatelessWidget {
  final String mediaUrl;
  final String mediaType;

  const _MediaContent({required this.mediaUrl, required this.mediaType});

  @override
  Widget build(BuildContext context) {
    if (mediaType == 'video') {
      return PostVideoPlayer(videoUrl: mediaUrl);
    } else {
      return _ImageMedia(mediaUrl: mediaUrl);
    }
  }
}

class _PostHeader extends ConsumerWidget {
  final Post post;
  const _PostHeader({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = MediaUtility.getProxyUrl(post.authorProfileImage ?? '');
    final currentUser = AuthService.currentUser;
    final isOwnPost = currentUser != null && post.authorId == currentUser.uid;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipOval(
          child: Container(
            color: Colors.grey[100],
            child: avatarUrl.isNotEmpty 
              ? CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _AvatarPlaceholder(name: post.authorName),
                  errorWidget: (context, url, error) => _AvatarPlaceholder(name: post.authorName),
                )
              : _AvatarPlaceholder(name: post.authorName),
          ),
        ),
      ),
      title: Text(
        post.authorName,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        _formatTimestamp(post.createdAt),
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      trailing: isOwnPost 
        ? PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteDialog(context, ref, post.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Delete Post', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          )
        : null,
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('Are you sure you want to permanently delete this post?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(postInteractionProvider).deletePost(id);
              Navigator.pop(context);
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}';
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  const _AvatarPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.grey[700],
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
    );
  }
}

class _ImageMedia extends StatelessWidget {
  final String mediaUrl;
  const _ImageMedia({required this.mediaUrl});

  @override
  Widget build(BuildContext context) {
    if (mediaUrl.isEmpty) return const SizedBox.shrink();

    final proxiedUrl = MediaUtility.getProxyUrl(mediaUrl);

    return RepaintBoundary(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border.symmetric(
            horizontal: BorderSide(color: Colors.grey[100]!, width: 0.5),
          ),
        ),
        child: CachedNetworkImage(
          imageUrl: proxiedUrl,
          fit: BoxFit.cover,
          maxWidthDiskCache: 1200, 
          fadeOutDuration: const Duration(milliseconds: 300),
          placeholder: (context, url) => Container(
            height: 250,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
          ),
          errorWidget: (context, url, error) => Container(
            height: 200,
            color: Colors.grey[100],
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.grey[400], size: 48),
                const SizedBox(height: 8),
                Text(
                  'Media unavailable',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PostActionRow extends ConsumerWidget {
  final Post post;
  const _PostActionRow({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interactionService = ref.read(postInteractionProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              post.isLiked ? Icons.favorite : Icons.favorite_border,
              color: post.isLiked ? Colors.red : Colors.grey[700],
              size: 26,
            ),
            onPressed: () => interactionService.toggleLike(post.id),
          ),
          Text(
            '${post.likeCount}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 20),
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, color: Colors.grey[700], size: 24),
            onPressed: () {}, 
          ),
          Text(
            '${post.commentCount}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.share_outlined, color: Colors.grey[700], size: 24),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
