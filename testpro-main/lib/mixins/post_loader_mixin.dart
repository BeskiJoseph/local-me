import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/paginated_response.dart';
import '../services/post_service.dart';
import '../utils/safe_error.dart';

/// Mixin that provides standardized post loading and pagination logic
/// Eliminates code duplication across screens that load posts
mixin PostLoaderMixin<T extends StatefulWidget> on State<T> {
  // Abstract properties that implementing classes must provide
  List<Post> get posts;
  set posts(List<Post> value);
  bool get isLoading;
  set isLoading(bool value);
  bool get hasMore;
  set hasMore(bool value);
  Map<String, bool> get likedPostIds;
  
  // Optional parameters
  String? get authorId => null;
  String? get feedType => null;
  String? get userCity => null;
  String? get userCountry => null;
  String? get mediaType => null;
  int get pageSize => 10;

  /// Standardized post loading with pagination support
  Future<void> loadPosts({
    bool refresh = false,
    Map<String, dynamic>? lastCursors,
  }) async {
    if (isLoading) return;
    if (!refresh && !hasMore && lastCursors == null) return;

    setState(() => isLoading = true);

    try {
      final response = await _fetchPosts(refresh: refresh, lastCursors: lastCursors);

      if (!mounted) return;

      final List<Post> newPosts = response.data;

      // Update liked post IDs
      for (var p in newPosts) {
        likedPostIds[p.id] = p.isLiked;
      }

      setState(() {
        if (refresh) {
          posts = newPosts; // Replace all posts on refresh
        } else {
          posts.addAll(newPosts); // Append for pagination
        }
        hasMore = response.hasMore;
        isLoading = false;
      });

      // Call optional post-load callback
      onPostsLoaded(newPosts, refresh);
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        onPostsError(e);
      }
    }
  }

  /// Fetch posts based on the configuration
  Future<PaginatedResponse<Post>> _fetchPosts({
    required bool refresh,
    Map<String, dynamic>? lastCursors,
  }) {
    if (authorId != null) {
      // Loading posts for specific author
      return PostService.getFilteredPostsPaginated(
        authorId: authorId!,
        limit: pageSize,
        lastCursors: lastCursors,
      );
    } else if (feedType != null) {
      // Loading posts for specific feed type
      return PostService.getPostsPaginated(
        feedType: feedType!,
        userCity: userCity,
        userCountry: userCountry,
        mediaType: mediaType,
        limit: pageSize,
        lastCursors: lastCursors,
      );
    } else {
      // Default: general posts
      return PostService.getPostsPaginated(
        feedType: 'global',
        limit: pageSize,
        lastCursors: lastCursors,
      );
    }
  }

  /// Optional callback called after posts are loaded successfully
  void onPostsLoaded(List<Post> posts, bool refresh) {
    // Override in implementing class if needed
  }

  /// Optional callback called when post loading fails
  void onPostsError(dynamic error) {
    debugPrint('Error loading posts: $error');
    // Override in implementing class for custom error handling
  }

  /// Add a new post to the beginning of the list (for new post creation)
  void addNewPost(Post post) {
    if (authorId != null && post.authorId != authorId) return;
    
    setState(() {
      posts.insert(0, post);
      likedPostIds[post.id] = post.isLiked;
    });
  }

  /// Standardized error handling for post operations
  void showError(dynamic error) {
    final message = safeErrorMessage(error, fallback: 'Failed to load posts. Please try again.');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  /// Standardized success message
  void showSuccess(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  /// Standardized loading widget
  Widget buildLoadingWidget() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  /// Standardized error widget
  Widget buildErrorWidget(String error, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            safeErrorMessage(error, fallback: 'Something went wrong'),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  /// Standardized empty state widget
  Widget buildEmptyWidget({String message = 'No posts found'}) {
    return Center(
      child: Text(message),
    );
  }

  /// Standardized pagination loading indicator
  Widget buildPaginationLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  /// Standardized retry footer for pagination
  Widget buildRetryFooter(VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text('Failed to load more posts'),
          TextButton(
            onPressed: onRetry,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
