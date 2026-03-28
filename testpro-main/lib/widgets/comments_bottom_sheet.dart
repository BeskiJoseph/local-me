import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/models/comment.dart';
import 'package:testpro/services/auth_service.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/socket_service.dart';
import 'package:testpro/shared/widgets/user_avatar.dart';
import 'package:testpro/core/utils/time_utils.dart';
import 'package:testpro/utils/safe_error.dart';
import 'package:testpro/core/state/post_state.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:async';

/// YouTube-style advanced comments bottom sheet
class CommentsBottomSheet extends ConsumerStatefulWidget {
  final Post post;

  const CommentsBottomSheet({super.key, required this.post});

  @override
  ConsumerState<CommentsBottomSheet> createState() => _CommentsBottomSheetState();

  static void show(BuildContext context, Post post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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

class _CommentsBottomSheetState extends ConsumerState<CommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  // Remove local _comments and _nextCursor as we will use the global cache
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSending = false;
  String _sortVersion = 'newest'; // 'newest' or 'top'
  
  StreamSubscription? _socketSub;
  
  // Track expanded replies
  final Map<String, List<Comment>> _repliesMap = {};
  final Set<String> _loadingReplies = {};
  final Set<String> _expandedReplies = {};

  void _setPostCommentCountDelta(int delta) {
    final postInStore = ref.read(postProvider(widget.post.id)) ?? widget.post;
    final nextCount = (postInStore.commentCount + delta).clamp(0, 1 << 30);
    ref
        .read(postStoreProvider.notifier)
        .updatePostPartially(widget.post.id, {'commentCount': nextCount});
  }

  void _setPostCommentCountExact(int count) {
    final normalized = count.clamp(0, 1 << 30);
    ref
        .read(postStoreProvider.notifier)
        .updatePostPartially(widget.post.id, {'commentCount': normalized});
  }

  void _upsertOptimisticTopLevelComment(Comment optimisticComment) {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    final existingComments = cache?.comments ?? const <Comment>[];
    final alreadyExists = existingComments.any((c) => c.id == optimisticComment.id);
    if (alreadyExists) return;

    ref.read(commentCacheProvider.notifier).updateCache(
      widget.post.id,
      [optimisticComment, ...existingComments],
      nextCursor: cache?.nextCursor,
    );
    _setPostCommentCountDelta(1);
  }

  void _removeOptimisticTopLevelComment(String optimisticId) {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    if (cache == null) return;

    final hadOptimistic = cache.comments.any((c) => c.id == optimisticId);
    if (!hadOptimistic) return;

    final updated = cache.comments.where((c) => c.id != optimisticId).toList();
    ref.read(commentCacheProvider.notifier).updateCache(
      widget.post.id,
      updated,
      nextCursor: cache.nextCursor,
    );
    _setPostCommentCountDelta(-1);
  }

  void _replaceOptimisticWithReal({
    required String optimisticId,
    required Comment realComment,
  }) {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    if (cache == null) {
      ref.read(commentCacheProvider.notifier).updateCache(
        widget.post.id,
        [realComment],
      );
      return;
    }

    final hasReal = cache.comments.any((c) => c.id == realComment.id);
    if (hasReal) {
      final withoutOptimistic = cache.comments
          .where((c) => c.id != optimisticId)
          .toList();
      ref.read(commentCacheProvider.notifier).updateCache(
        widget.post.id,
        withoutOptimistic,
        nextCursor: cache.nextCursor,
      );
      return;
    }

    final optimisticIndex = cache.comments.indexWhere((c) => c.id == optimisticId);
    if (optimisticIndex != -1) {
      final updated = List<Comment>.from(cache.comments);
      updated[optimisticIndex] = realComment;
      ref.read(commentCacheProvider.notifier).updateCache(
        widget.post.id,
        updated,
        nextCursor: cache.nextCursor,
      );
      return;
    }

    ref.read(commentCacheProvider.notifier).updateCache(
      widget.post.id,
      [realComment, ...cache.comments],
      nextCursor: cache.nextCursor,
    );
  }

  void _handleIncomingSocketComment(Comment incoming) {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    final currentUserId = AuthService.currentUser?.uid;
    final isReply = incoming.parentId != null;

    if (isReply) {
      final parentId = incoming.parentId!;
      final existingReplies = _repliesMap[parentId];
      if (existingReplies != null) {
        final alreadyExists = existingReplies.any((c) => c.id == incoming.id);
        if (!alreadyExists) {
          setState(() {
            _repliesMap[parentId] = [incoming, ...existingReplies];
          });
        }
      }
      return;
    }

    if (cache == null) {
      ref.read(commentCacheProvider.notifier).updateCache(
        widget.post.id,
        [incoming],
      );
      _setPostCommentCountDelta(1);
      return;
    }

    // Dedup by real server ID first.
    if (cache.comments.any((c) => c.id == incoming.id)) return;

    // Reconcile "temp_*" optimistic comment from current user to avoid double count.
    final maybeTempIndex = cache.comments.indexWhere(
      (c) =>
          c.id.startsWith('temp_') &&
          c.authorId == currentUserId &&
          c.authorId == incoming.authorId &&
          c.text == incoming.text &&
          incoming.createdAt.difference(c.createdAt).abs() <
              const Duration(seconds: 30),
    );

    if (maybeTempIndex != -1) {
      final updated = List<Comment>.from(cache.comments);
      updated[maybeTempIndex] = incoming;
      ref.read(commentCacheProvider.notifier).updateCache(
        widget.post.id,
        updated,
        nextCursor: cache.nextCursor,
      );
      return;
    }

    ref.read(commentCacheProvider.notifier).updateCache(
      widget.post.id,
      [incoming, ...cache.comments],
      nextCursor: cache.nextCursor,
    );
    _setPostCommentCountDelta(1);
  }

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() => setState(() {}));
    _scrollController.addListener(_scrollListener);
    
    // Join socket room for live updates
    SocketService.joinPost(widget.post.id);

    // 🔥 Listen for real-time updates
    _socketSub = SocketService.updates.listen((data) {
      if (!mounted) return;
      
      // Match the backend payload: { postId, commentCount, newComment: { ... } }
      if (data['postId'] == widget.post.id) {
        final serverCount = data['commentCount'];
        if (serverCount is int) {
          _setPostCommentCountExact(serverCount);
        }
        if (data['newComment'] != null) {
          final newComment = Comment.fromJson(
            Map<String, dynamic>.from(data['newComment']),
          );
          _handleIncomingSocketComment(newComment);
        }
      }
    });
    
    // 🔥 Cache-First Strategy
    final cacheMap = ref.read(commentCacheProvider);
    final cache = cacheMap[widget.post.id];
    
    if (cache != null) {
      _isLoading = false;
      
      final age = DateTime.now().difference(cache.lastFetched);
      if (age > const Duration(seconds: 30)) {
        // Background refresh
        _loadComments(refresh: true, background: true);
      }
    } else {
      _loadComments(refresh: true);
    }

    Future.microtask(() {
      if (mounted) _commentFocus.requestFocus();
    });
  }

  void _scrollListener() {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    final nextCursor = cache?.nextCursor;

    // 🔥 Improved pagination trigger: 3 items from bottom (approx 400px)
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400 &&
        !_isLoadingMore && nextCursor != null) {
      _loadComments(refresh: false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _scrollController.dispose();
    _socketSub?.cancel();
    SocketService.leavePost(widget.post.id);
    super.dispose();
  }

  Future<void> _loadComments({required bool refresh, bool background = false}) async {
    final cache = ref.read(commentCacheProvider)[widget.post.id];
    final currentCursor = refresh ? null : cache?.nextCursor;

    if (refresh) {
      if (!background) {
        setState(() {
          _isLoading = true;
        });
      }
    } else {
      if (_isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final response = await BackendService.getComments(
        widget.post.id, 
        afterId: currentCursor,
        sort: _sortVersion,
        limit: 20
      );

      if (response.success) {
        final List<Comment> newCommentsList = (response.data as List).map((c) => Comment.fromJson(c as Map<String, dynamic>)).toList();
        final String? cursor = response.pagination?.cursor;

        if (mounted) {
          // 🔥 Sync to global cache
          ref.read(commentCacheProvider.notifier).updateCache(
            widget.post.id, 
            newCommentsList, 
            nextCursor: cursor,
            isAppend: !refresh,
          );

          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(safeErrorMessage(response.error))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _sendComment({String? parentId}) async {
    final text = _commentController.text.trim();
    final user = AuthService.currentUser;

    if (text.isEmpty || user == null) return;

    // --- Local Spam Filter ---
    // 🔥 IMPROVED: More sophisticated spam detection with word boundaries and repetition check
    final spamPatterns = [
      RegExp(r'\b(buy\s+bitcoin|crypto|investment\s+scheme)\b', caseSensitive: false),
      RegExp(r'\bfree\s+(followers|likes|money|gift)\b', caseSensitive: false),
      RegExp(r'\b(click\s+here|limited\s+time|act\s+now)\b', caseSensitive: false),
    ];
    
    // Check for spam patterns
    final hasSpamPattern = spamPatterns.any((pattern) => pattern.hasMatch(text));
    
    // Check for excessive repetition (e.g., "!!!!!!!!!" or "buy buy buy")
    final hasExcessiveRepetition = RegExp(r'(.)\1{4,}').hasMatch(text) || // 5+ same chars
        RegExp(r'\b(\w+)\s+\1\s+\1', caseSensitive: false).hasMatch(text); // repeated words
    
    if (hasSpamPattern || hasExcessiveRepetition) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your comment contains prohibited content.')),
      );
      return;
    }

    if (text.length > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment is too long. Maximum 300 characters.')),
      );
      return;
    }
    final optimisticComment = Comment(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      postId: widget.post.id,
      authorId: user.uid,
      authorName: user.displayName ?? 'You',
      authorProfileImage: user.photoURL,
      text: text,
      createdAt: DateTime.now(),
      parentId: parentId,
      likeCount: 0,
      replyCount: 0,
    );

    setState(() {
      if (parentId == null) {
        _upsertOptimisticTopLevelComment(optimisticComment);
        
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        _repliesMap[parentId] ??= [];
        _repliesMap[parentId]!.add(optimisticComment);
        _expandedReplies.add(parentId);
      }
      _isSending = true;
    });

    _commentController.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

    try {
      final response = await BackendService.addComment(widget.post.id, text, parentId: parentId);
      if (response.success) {
        final realComment = Comment.fromJson(response.data!);
        if (mounted) {
          if (parentId == null) {
             _replaceOptimisticWithReal(
               optimisticId: optimisticComment.id,
               realComment: realComment,
             );
          } else {
             setState(() {
                final idx = _repliesMap[parentId]!.indexWhere((c) => c.id == optimisticComment.id);
                if (idx != -1) _repliesMap[parentId]![idx] = realComment;
             });
          }
        }
      } else {
        throw Exception(response.error);
      }
    } catch (e) {
      if (mounted) {
        if (parentId == null) {
          _removeOptimisticTopLevelComment(optimisticComment.id);
        } else {
          setState(() {
            _repliesMap[parentId]!.removeWhere((c) => c.id == optimisticComment.id);
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(safeErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  bool get _canSend => _commentController.text.trim().isNotEmpty && !_isSending;

  Future<void> _loadReplies(String commentId) async {
    if (_loadingReplies.contains(commentId)) return;
    
    setState(() {
      _loadingReplies.add(commentId);
      _expandedReplies.add(commentId);
    });

    try {
      final response = await BackendService.getReplies(commentId);
      if (response.success && mounted) {
        final replies = (response.data as List).map((r) => Comment.fromJson(r)).toList();
        setState(() {
          _repliesMap[commentId] = replies;
          _loadingReplies.remove(commentId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingReplies.remove(commentId));
      }
    }
  }

  final Set<String> _togglingCommentLikes = {};

  Future<void> _toggleCommentLike(Comment comment) async {
    if (_togglingCommentLikes.contains(comment.id)) return;
    
    HapticFeedback.lightImpact();
    _togglingCommentLikes.add(comment.id);
    
    final bool currentlyLiked = comment.isLiked;
    final int newCount = currentlyLiked ? comment.likeCount - 1 : comment.likeCount + 1;
    final updated = comment.copyWith(isLiked: !currentlyLiked, likeCount: newCount);

    // 1. Optimistic Update
    if (comment.parentId == null) {
      // Top-level comment: Update global cache for reactivity
      final cache = ref.read(commentCacheProvider)[widget.post.id];
      if (cache != null) {
        final updatedList = cache.comments.map((c) => c.id == comment.id ? updated : c).toList();
        ref.read(commentCacheProvider.notifier).updateCache(widget.post.id, updatedList);
      }
    } else {
      // Reply: Update local replies map
      setState(() {
        final idx = _repliesMap[comment.parentId]?.indexWhere((c) => c.id == comment.id) ?? -1;
        if (idx != -1) {
          _repliesMap[comment.parentId]![idx] = updated;
        }
      });
    }

    try {
      await BackendService.toggleCommentLike(comment.id);
      
      // If top-level, we might want to sync back to cache (though current implementation only modifies local if you refresh)
      // Since we want full reactivity, let's update global cache if it's there
      if (comment.parentId == null) {
        final cache = ref.read(commentCacheProvider)[widget.post.id];
        if (cache != null) {
          final updatedComments = cache.comments.map((c) => c.id == comment.id ? updated : c).toList();
          ref.read(commentCacheProvider.notifier).updateCache(widget.post.id, updatedComments);
        }
      }
    } catch (e) {
      // Rollback
      if (mounted) {
        setState(() {
          if (comment.parentId == null) {
             // Rollback cache
             final cache = ref.read(commentCacheProvider)[widget.post.id];
             if (cache != null) {
               final rolledBack = cache.comments.map((c) => c.id == comment.id ? comment : c).toList();
               ref.read(commentCacheProvider.notifier).updateCache(widget.post.id, rolledBack);
             }
          } else {
            final idx = _repliesMap[comment.parentId]!.indexWhere((c) => c.id == comment.id);
            if (idx != -1) _repliesMap[comment.parentId]![idx] = comment;
          }
        });
      }
    } finally {
      _togglingCommentLikes.remove(comment.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 Watch global cache for reactivity
    final cacheMap = ref.watch(commentCacheProvider);
    final cache = cacheMap[widget.post.id];
    final comments = cache?.comments ?? [];

    return Column(
      children: [
        // Header
        _buildHeader(),
        
        // Sorting Toggle
        _buildSortBar(),

        // Comments Area
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF006D6D)))
            : _buildCommentsList(comments),
        ),

        // Input
        _buildInputArea(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Column(
        children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade900)),
        ],
      ),
    );
  }

  Widget _buildSortBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _sortChip('Newest', 'newest'),
          const SizedBox(width: 8),
          _sortChip('Top', 'top'),
        ],
      ),
    );
  }

  Widget _sortChip(String label, String value) {
    final isActive = _sortVersion == value;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          HapticFeedback.selectionClick();
          setState(() => _sortVersion = value);
          _loadComments(refresh: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF006D6D).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? const Color(0xFF006D6D) : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.bold : FontWeight.w500, color: isActive ? const Color(0xFF006D6D) : Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildCommentsList(List<Comment> comments) {
    if (comments.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No comments yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Be the first to share your thoughts', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
            const SizedBox(height: 12),
            TextButton(onPressed: () => _loadComments(refresh: true), child: const Text('Refresh')),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: comments.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == comments.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _CommentThread(
          comment: comments[index],
          replies: _repliesMap[comments[index].id] ?? [],
          isExpanded: _expandedReplies.contains(comments[index].id),
          isLoadingReplies: _loadingReplies.contains(comments[index].id),
          onLike: () => _toggleCommentLike(comments[index]),
          onReplyClick: () => _loadReplies(comments[index].id),
          onLikeReply: (r) => _toggleCommentLike(r),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade100))),
      child: Row(
        children: [
          UserAvatar(radius: 16, imageUrl: AuthService.currentUser?.photoURL, name: AuthService.currentUser?.displayName ?? 'User'),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _commentController,
              focusNode: _commentFocus,
              decoration: const InputDecoration(hintText: 'Add a comment...', border: InputBorder.none, hintStyle: TextStyle(fontSize: 14), counterText: ''),
              style: const TextStyle(fontSize: 14),
              maxLines: null,
              maxLength: 300,
            ),
          ),
          IconButton(
            icon: _isSending 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : Icon(Icons.send_rounded, color: _canSend ? const Color(0xFF006D6D) : Colors.grey.shade400),
            onPressed: _canSend ? _sendComment : null,
          ),
        ],
      ),
    );
  }
}

class _CommentThread extends StatelessWidget {
  final Comment comment;
  final List<Comment> replies;
  final bool isExpanded;
  final bool isLoadingReplies;
  final VoidCallback onLike;
  final VoidCallback onReplyClick;
  final Function(Comment) onLikeReply;

  const _CommentThread({
    required this.comment,
    required this.replies,
    required this.isExpanded,
    required this.isLoadingReplies,
    required this.onLike,
    required this.onReplyClick,
    required this.onLikeReply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CommentItem(comment: comment, onLike: onLike, onReply: onReplyClick),
        if (comment.replyCount > 0 && !isExpanded)
          _ViewRepliesButton(commentId: comment.id, count: comment.replyCount, onClick: onReplyClick),
        if (isExpanded) ...[
          if (isLoadingReplies)
            const Padding(padding: EdgeInsets.only(left: 50, top: 8, bottom: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))),
          ...replies.map((r) => Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _CommentItem(comment: r, onLike: () => onLikeReply(r)),
          )),
        ],
        const Divider(height: 1, indent: 50),
      ],
    );
  }
}

class _CommentItem extends StatelessWidget {
  final Comment comment;
  final VoidCallback onLike;
  final VoidCallback? onReply;

  const _CommentItem({required this.comment, required this.onLike, this.onReply});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(radius: 16, imageUrl: comment.authorProfileImage, name: comment.authorName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.authorName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(TimeUtils.formatTimeAgo(comment.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
                const SizedBox(height: 4),
                _RichCommentText(text: comment.text),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(onTap: onLike, child: Icon(comment.isLiked ? Icons.favorite : Icons.favorite_border, size: 16, color: comment.isLiked ? Colors.red : Colors.grey)),
                    const SizedBox(width: 4),
                    Text(comment.likeCount.toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(width: 24),
                    if (onReply != null)
                      GestureDetector(onTap: onReply, child: const Text('Reply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RichCommentText extends StatelessWidget {
  final String text;
  const _RichCommentText({required this.text});

  @override
  Widget build(BuildContext context) {
    final List<TextSpan> children = [];
    final RegExp regExp = RegExp(r"(@\w+|#\w+)");
    
    int lastIndex = 0;
    for (final Match match in regExp.allMatches(text)) {
      if (match.start > lastIndex) {
        children.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final String matchText = match.group(0)!;
      final bool isMention = matchText.startsWith('@');
      
      children.add(TextSpan(
        text: matchText,
        style: TextStyle(
          color: isMention ? const Color(0xFF2563EB) : const Color(0xFF006D6D),
          fontWeight: FontWeight.w700,
        ),
      ));
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      children.add(TextSpan(text: text.substring(lastIndex)));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF3A3A3C), fontFamily: 'Inter'),
        children: children,
      ),
    );
  }
}

class _ViewRepliesButton extends StatelessWidget {
  final String commentId;
  final int count;
  final VoidCallback onClick;
  const _ViewRepliesButton({required this.commentId, required this.count, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, bottom: 8),
      child: InkWell(
        onTap: onClick,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 30, height: 1, color: const Color(0xFF006D6D).withValues(alpha: 0.3)),
              const SizedBox(width: 12),
              Text(
                'View $count replies', 
                style: const TextStyle(
                  fontSize: 12, 
                  fontWeight: FontWeight.w700, 
                  color: Color(0xFF006D6D),
                  letterSpacing: 0.2
                )
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF006D6D)),
            ],
          ),
        ),
      ),
    );
  }
}
