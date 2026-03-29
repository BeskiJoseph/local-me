import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../core/state/post_state.dart';
import '../core/utils/haptic_service.dart';
import 'package:testpro/services/backend_service.dart';

/// Centralized service for handling user interactions (like, follow)
/// Eliminates code duplication across all widgets
class InteractionService {
  /// Handle like/unlike action with optimistic updates and race condition protection
  static Future<void> toggleLike({
    required String postId,
    required WidgetRef ref,
    VoidCallback? onBusy,
    VoidCallback? onReady,
  }) async {
    final notifier = ref.read(postStoreProvider.notifier);
    final post = ref.read(postProvider(postId));
    
    if (post == null) return;

    final bool isLiked = post.isLiked;
    final int likeCount = post.likeCount;
    final bool newTarget = !isLiked;
    final int newCount = likeCount + (newTarget ? 1 : -1);

    if (newTarget) HapticService.medium();

    final int version = DateTime.now().millisecondsSinceEpoch;

    // 1. Optimistic Update
    notifier.setActionVersion(postId, 'like', version);
    notifier.updatePostPartially(postId, {
      'isLiked': newTarget,
      'likeCount': newCount,
    });

    onBusy?.call();

    try {
      final response = await BackendService.toggleLike(postId);

      // 2. Race Condition Check
      final latestVersion = ref.read(postActionVersionProvider((postId, 'like')));
      if (latestVersion != version) return;

      if (!response.success) {
        _rollbackLike(postId, ref, isLiked, likeCount);
        ErrorHandler.showError(
          "Unable to update like. Please try again.",
        );
      } else {
        // Sync with server response if available
        final data = response.data;
        if (data != null) {
          notifier.updatePostPartially(postId, {
            'isLiked': data['isLiked'],
            'likeCount': data['likeCount'],
          });
        }
      }
    } catch (e) {
      _rollbackLike(postId, ref, isLiked, likeCount);
      ErrorHandler.showError(
        "An error occurred while updating like.",
      );
    } finally {
      onReady?.call();
    }
  }

  /// Handle follow/unfollow action with optimistic updates and race condition protection
  /// Updates ALL posts by the same author to maintain consistency across the feed
  static Future<void> toggleFollow({
    required String targetUserId,
    required String postId,
    required String authorId,
    required WidgetRef ref,
    VoidCallback? onBusy,
    VoidCallback? onReady,
  }) async {
    final notifier = ref.read(postStoreProvider.notifier);
    final post = ref.read(postProvider(postId));
    
    if (post == null) return;

    final bool currentFollowing = post.isFollowing;
    final bool newState = !currentFollowing;

    HapticFeedback.selectionClick();

    final int version = DateTime.now().millisecondsSinceEpoch;

    // 1. Optimistic Update - Update ALL posts by this author across the feed
    notifier.setActionVersion(postId, 'follow', version);
    
    // 🔥 CRITICAL FIX: Update ALL posts by this author, not just the current post
    notifier.updatePostPartiallyByAuthor(authorId, {'isFollowing': newState});

    onBusy?.call();

    try {
      final response = await BackendService.toggleFollow(targetUserId);

      // 2. Race Condition Check
      final latestVersion = ref.read(postActionVersionProvider((postId, 'follow')));
      if (latestVersion != version) return;

      if (!response.success) {
        // Rollback ALL posts by this author
        notifier.updatePostPartiallyByAuthor(authorId, {'isFollowing': currentFollowing});
        ErrorHandler.showError(
          "Unable to update follow status. Please try again.",
        );
      } else {
        // Sync with server response - update all posts by this author
        final isNowFollowing = response.data ?? newState;
        notifier.updatePostPartiallyByAuthor(authorId, {'isFollowing': isNowFollowing});
      }
    } catch (e) {
      // Rollback ALL posts by this author on error
      notifier.updatePostPartiallyByAuthor(authorId, {'isFollowing': currentFollowing});
      ErrorHandler.showError(
        "An error occurred while updating follow status.",
      );
    } finally {
      onReady?.call();
    }
  }

  /// Handle follow/unfollow for user profile (not tied to a post)
  static Future<void> toggleFollowUser({
    required String targetUserId,
    required WidgetRef ref,
    VoidCallback? onBusy,
    VoidCallback? onReady,
    Function(bool)? onResult,
  }) async {
    onBusy?.call();

    try {
      final response = await BackendService.toggleFollow(targetUserId);
      
      if (response.success) {
        onResult?.call(response.data ?? false);
      } else {
        ErrorHandler.showError(
          "Unable to update follow. Please try again.",
        );
      }
    } catch (e) {
      ErrorHandler.showError(
        "An error occurred while updating follow.",
      );
    } finally {
      onReady?.call();
    }
  }

  static void _rollbackLike(String postId, WidgetRef ref, bool isLiked, int likeCount) {
    final notifier = ref.read(postStoreProvider.notifier);
    notifier.updatePostPartially(postId, {
      'isLiked': isLiked,
      'likeCount': likeCount,
    });
  }

  // BUG-011: Removed dead _rollbackFollow method. Follow rollback uses
  // notifier.updatePostPartiallyByAuthor() directly in toggleFollow.
}

/// Utility for error handling
class ErrorHandler {
  static void showError(String message, {BuildContext? context}) {
    if (context != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } else {
      // Find current context if not provided
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _findCurrentContext();
        if (context != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
          );
        }
      });
    }
  }

  static void showSuccess(String message, {BuildContext? context}) {
    if (context != null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _findCurrentContext();
        if (context != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.green),
          );
        }
      });
    }
  }

  static BuildContext? _findCurrentContext() {
    // Try to find current context from navigator
    return navigatorKey.currentContext;
  }

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
