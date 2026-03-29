import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../services/backend_service.dart';
import '../store/post_store.dart';
import '../models/post.dart';

import '../services/post_lifecycle_service.dart';
import '../../services/post_service.dart' as legacy;

/// The ONLY service responsible for handling user interactions in the new system.
class PostInteractionService {
  final ProviderRef ref;
  
  PostInteractionService(this.ref);

  /// Creates a new post and notifies the lifecycle bus.
  Future<void> createPost({
    required String title,
    required String body,
    String? mediaUrl,
    String mediaType = 'none',
    double? latitude,
    double? longitude,
    String? city,
    String? country,
  }) async {
    try {
      final oldPost = await legacy.PostService.createPost(
        title: title,
        body: body,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        latitude: latitude,
        longitude: longitude,
        city: city,
        country: country,
      );

      // Map to NEW model
      final post = Post(
        id: oldPost.id,
        authorId: oldPost.authorId,
        authorName: oldPost.authorName,
        authorProfileImage: oldPost.authorProfileImage,
        title: oldPost.title,
        body: oldPost.body,
        mediaUrl: oldPost.mediaUrl,
        mediaType: oldPost.mediaType,
        likeCount: oldPost.likeCount,
        commentCount: oldPost.commentCount,
        createdAt: oldPost.createdAt,
        isLiked: oldPost.isLiked,
        isFollowing: oldPost.isFollowing,
      );

      // Notify lifecycle bus (Auto-injects to Home and Profile)
      ref.read(postLifecycleProvider).notifyCreated(post);
    } catch (e) {
      // Handle error if needed
    }
  }

  /// Deletes a post and notifies the lifecycle bus.
  Future<void> deletePost(String postId) async {
    try {
      await legacy.PostService.deletePost(postId);
      
      // Notify lifecycle bus (Auto-removes from everywhere)
      ref.read(postLifecycleProvider).notifyDeleted(postId);
    } catch (e) {
      // Handle error if needed
    }
  }

  /// Toggles the like status of a post with Optimistic Update.
  Future<void> toggleLike(String postId) async {
    final notifier = ref.read(postStoreProvider.notifier);
    final postSnapshot = notifier.getPost(postId);
    
    // SAFE UPDATE CHECK: Exit if post not in store yet or stale
    if (postSnapshot == null) return;

    final bool wasLiked = postSnapshot.isLiked;
    final int originalLikeCount = postSnapshot.likeCount;

    // 1. OPTIMISTIC UPDATE: Update PostStore instantly
    notifier.updatePost(postId, (post) => post.copyWith(
      isLiked: !wasLiked,
      likeCount: wasLiked ? post.likeCount - 1 : post.likeCount + 1,
    ));

    try {
      // 2. BACKEND CALL: Existing backend logic
      final response = await BackendService.toggleLike(postId);
      
      if (!response.success) {
        // 3. ROLLBACK: Revert to previous state if server fails
        notifier.updatePost(postId, (post) => post.copyWith(
          isLiked: wasLiked,
          likeCount: originalLikeCount,
        ));
      } else {
        // Optional: Sync with server data if needed (e.g., precise counts)
        if (response.data != null) {
          final serverData = response.data as Map<String, dynamic>;
          notifier.updatePost(postId, (post) => post.copyWith(
            isLiked: serverData['isLiked'] ?? !wasLiked,
            likeCount: serverData['likeCount'] ?? originalLikeCount + (wasLiked ? -1 : 1),
          ));
        }
      }
    } catch (e) {
      // 3. ROLLBACK: Network failure
      notifier.updatePost(postId, (post) => post.copyWith(
        isLiked: wasLiked,
        likeCount: originalLikeCount,
      ));
    }
  }

  /// Toggles follow status for an author across the ENTIRE application.
  Future<void> toggleFollow(String authorId, String targetPostId) async {
    final notifier = ref.read(postStoreProvider.notifier);
    final postSnapshot = notifier.getPost(targetPostId);
    
    if (postSnapshot == null) return;

    final bool wasFollowing = postSnapshot.isFollowing;

    // 1. OPTIMISTIC UPDATE: Update ALL posts by this author in memory
    notifier.updatePostsByAuthor(authorId, (post) => post.copyWith(
      isFollowing: !wasFollowing,
    ));

    try {
      // 2. BACKEND CALL
      final response = await BackendService.toggleFollow(authorId);
      
      if (!response.success) {
        // 3. ROLLBACK
        notifier.updatePostsByAuthor(authorId, (post) => post.copyWith(
          isFollowing: wasFollowing,
        ));
      } else {
        // Sync with server if needed
        final serverFollowing = response.data as bool? ?? !wasFollowing;
        notifier.updatePostsByAuthor(authorId, (post) => post.copyWith(
          isFollowing: serverFollowing,
        ));
      }
    } catch (e) {
      // 3. ROLLBACK
      notifier.updatePostsByAuthor(authorId, (post) => post.copyWith(
        isFollowing: wasFollowing,
      ));
    }
  }
}

/// Interaction Service Provider
final postInteractionProvider = Provider((ref) => PostInteractionService(ref));
