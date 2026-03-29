import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/post.dart';

/// The Single Source of Truth for all Post data in the application.
/// 
/// Responsibility: 
/// - Maintain an central in-memory database of all fetched posts.
/// - Ensure each post only exists ONCE in memory.
/// - Provide targeted update capabilities.
class PostStore extends StateNotifier<Map<String, Post>> {
  PostStore() : super({});

  /// Upsert (Update or Insert) a single post into the store.
  void upsertPost(Post post) {
    state = {
      ...state,
      post.id: post,
    };
  }

  /// Bulk upsert multiple posts into the store.
  void upsertPosts(List<Post> posts) {
    final newState = Map<String, Post>.from(state);
    for (final post in posts) {
      newState[post.id] = post;
    }
    state = newState;
  }

  /// Update a specific post by its ID using an update function.
  /// (Useful for likes, follows, etc. without needing the full object)
  /// 🔥 SAFE UPDATE CHECK: Prevents updates to non-existent posts.
  void updatePost(String id, Post Function(Post) updateFn) {
    final post = state[id];
    if (post != null) {
      final updated = updateFn(post);
      state = {
        ...state,
        id: updated,
      };
    }
  }

  /// Bulk update all posts by a specific author.
  /// (Useful for follow/unfollow updates across the entire feed).
  void updatePostsByAuthor(String authorId, Post Function(Post) updateFn) {
    final newState = Map<String, Post>.from(state);
    bool changed = false;
    
    newState.forEach((id, post) {
      if (post.authorId == authorId) {
        newState[id] = updateFn(post);
        changed = true;
      }
    });

    if (changed) {
      state = newState;
    }
  }

  /// Retrieve a specific post by ID.
  Post? getPost(String id) => state[id];

  /// Bulk retrieve posts for a list of IDs.
  /// (Useful for feeds that only store IDs).
  List<Post> getPosts(List<String> ids) {
    return ids.map((id) => state[id]).whereType<Post>().toList();
  }

  /// Remove a post from the store (e.g. on deletion).
  void removePost(String id) {
    if (state.containsKey(id)) {
      final newState = Map<String, Post>.from(state);
      newState.remove(id);
      state = newState;
    }
  }

  /// Clear the store (useful for full re-init or logouts).
  void clear() {
    state = {};
  }
}

/// Global provider for the PostStore.
/// Everything in the app that wants latest post data must watch this.
final postStoreProvider = StateNotifierProvider<PostStore, Map<String, Post>>((ref) {
  return PostStore();
});

/// ✅ Targeted Provider for a single post by ID.
/// (Used in PostCard and ReelPostItem for high-performance selective rebuilds)
final individualPostProvider = Provider.family<Post?, String>((ref, id) {
  return ref.watch(postStoreProvider.select((posts) => posts[id]));
});
