import 'dart:async';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../models/post.dart';

enum PostEvent { created, deleted }

class PostLifecycleEvent {
  final Post? post;
  final String? postId;
  final PostEvent type;

  PostLifecycleEvent({this.post, this.postId, required this.type});
}

/// A global event bus for post lifecycle changes.
/// 🧱 Burn-in Test 1 & 4: Ensures cross-screen synchronization for creation/deletion.
class PostLifecycleService {
  final _controller = StreamController<PostLifecycleEvent>.broadcast();

  Stream<PostLifecycleEvent> get events => _controller.stream;

  /// Broadcast that a new post has been created.
  void notifyCreated(Post post) {
    _controller.add(PostLifecycleEvent(post: post, type: PostEvent.created));
  }

  /// Broadcast that a post has been deleted.
  void notifyDeleted(String postId) {
    _controller.add(PostLifecycleEvent(postId: postId, type: PostEvent.deleted));
  }

  void dispose() {
    _controller.close();
  }
}

final postLifecycleProvider = Provider((ref) {
  final service = PostLifecycleService();
  ref.onDispose(() => service.dispose());
  return service;
});
