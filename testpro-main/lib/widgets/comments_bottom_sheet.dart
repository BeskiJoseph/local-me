import 'package:flutter/material.dart';
import '../models/post.dart';
import '../models/comment.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../services/comment_service.dart';
import '../shared/widgets/user_avatar.dart';
import '../core/utils/time_utils.dart';

String _formatTimeAgo(DateTime timestamp) {
  return TimeUtils.formatTimeAgo(timestamp);
}

/// Instagram-style comments bottom sheet
class CommentsBottomSheet extends StatefulWidget {
  final Post post;

  const CommentsBottomSheet({super.key, required this.post});

  @override
  State<CommentsBottomSheet> createState() => _CommentsBottomSheetState();

  /// Show the comments bottom sheet
  static void show(BuildContext context, Post post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return CommentsBottomSheet(post: post);
        },
      ),
    );
  }
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      final comments = await CommentService.getComments(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    final user = AuthService.currentUser;

    if (text.isEmpty || user == null) return;

    // --- Optimistic UI Start ---
    final optimisticComment = Comment(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      postId: widget.post.id,
      authorId: user.uid,
      authorName: user.displayName ?? 'You',
      authorProfileImage: user.photoURL,
      text: text,
      createdAt: DateTime.now(),
      likeCount: 0,
      isLiked: false,
    );

    setState(() {
      _comments.add(optimisticComment);
      _isSending = true; // Still show spinner on the send button but not the whole list
    });

    _commentController.clear();
    FocusScope.of(context).unfocus();

    // Scroll to bottom immediately for the optimistic comment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    // --- Optimistic UI End ---

    try {
      final response = await BackendService.addComment(widget.post.id, text);
      if (response.success) {
        // Sync with backend in background
        await _loadComments(showLoader: false);
      } else {
        throw Exception(response.error ?? 'Failed to add comment');
      }
    } catch (e) {
      // Rollback optimistic comment on error
      if (mounted) {
        setState(() {
          _comments.removeWhere((c) => c.id == optimisticComment.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleCommentLike(Comment comment) async {
    final index = _comments.indexWhere((c) => c.id == comment.id);
    if (index == -1) return;

    final updatedComment = comment.copyWith(
      isLiked: !comment.isLiked,
      likeCount: comment.isLiked ? comment.likeCount - 1 : comment.likeCount + 1,
    );

    setState(() {
      _comments[index] = updatedComment;
    });

    try {
      // TODO: Implement BackendService.toggleCommentLike when endpoint is available
      // await BackendService.toggleCommentLike(comment.postId, comment.id);
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _comments[index] = comment;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with drag handle
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              // Title
              Text(
                'Comments',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_comments.length} comments',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),

        // Comments list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No comments yet',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Be the first to comment',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        return _buildCommentItem(comment);
                      },
                    ),
        ),

        // Comment input
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Row(
            children: [
              // User avatar
              UserAvatar(
                imageUrl: AuthService.currentUser?.photoURL,
                name: AuthService.currentUser?.displayName ?? 'User',
                radius: 18,
              ),
              const SizedBox(width: 12),
              // Text field
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendComment(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Send button
              GestureDetector(
                onTap: _isSending ? null : _sendComment,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF006D6D),
                    shape: BoxShape.circle,
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentItem(Comment comment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          UserAvatar(
            imageUrl: comment.authorProfileImage,
            name: comment.authorName,
            radius: 18,
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username and time
                Row(
                  children: [
                    Text(
                      comment.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimeAgo(comment.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Comment text
                Text(
                  comment.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
