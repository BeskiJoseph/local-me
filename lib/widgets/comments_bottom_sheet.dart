import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/post_state.dart';

class CommentsBottomSheet extends StatefulWidget {
  final String postId;
  const CommentsBottomSheet({Key? key, required this.postId}) : super(key: key);

  @override
  _CommentsBottomSheetState createState() => _CommentsBottomSheetState();
}

class _CommentsBottomSheetState extends State<CommentsBottomSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final post = ref.watch(postProvider(widget.postId));
        final store = ref.read(postStoreProvider.notifier);
        final comments = post?.comments ?? [];
        return Scaffold(
          appBar: AppBar(title: Text('Comments')),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: comments.length,
                  itemBuilder: (ctx, idx) {
                    final c = comments[idx];
                    return ListTile(title: Text(c.text));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(hintText: 'Add a comment'),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send),
                      onPressed: () {
                        final text = _controller.text.trim();
                        if (text.isEmpty) return;
                        final newComment = Comment(
                          id: UniqueKey().toString(),
                          authorId: 'currentUser',
                          text: text,
                        );
                        // Prevent duplicates by ID
                        if (comments.any((c) => c.id == newComment.id)) return;
                        store.addComment(widget.postId, newComment);
                        _controller.clear();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
