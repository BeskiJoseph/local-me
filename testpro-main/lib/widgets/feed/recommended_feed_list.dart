import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../models/post.dart';
import '../post_card.dart';
import '../../screens/interest_picker_screen.dart';

/// A specialized widget to handle the personalized recommendation feed
class RecommendedFeedList extends StatefulWidget {
  const RecommendedFeedList({super.key});

  @override
  State<RecommendedFeedList> createState() => _RecommendedFeedListState();
}

class _RecommendedFeedListState extends State<RecommendedFeedList> {
  final ScrollController _scrollController = ScrollController();
  final List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    _loadMorePosts();
    _scrollController.addListener(() {
      if (_scrollController.hasClients && 
          _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _loadMorePosts();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMorePosts({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;

    if (refresh) {
      if (mounted) {
        setState(() {
          _posts.clear();
          _hasMore = true;
          _lastDocument = null;
          _isLoading = true;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = true);
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final newPosts = await FirestoreService.getRecommendedFeed(
        userId: user.uid,
        sessionId: _sessionId,
        lastDocument: _lastDocument,
        limit: 10,
      );

      if (mounted) {
        setState(() {
          // If we are refreshing, we already cleared list.
          // If not refreshing, we append.
          
          if (refresh) {
            _posts.clear(); // Safety clear again
            _posts.addAll(newPosts);
          } else {
            // Deduplicate just in case
            final existingIds = _posts.map((p) => p.id).toSet();
            final uniqueNew = newPosts.where((p) => !existingIds.contains(p.id));
            _posts.addAll(uniqueNew);
          }

          if (newPosts.length < 10) _hasMore = false;
          
          // For pagination in V3, usually we update _lastDocument if strict pagination,
          // but mixed feed strategy is complex. Here we assume generic pagination/session.
        });
      }
    } catch (e) {
      debugPrint('Error loading recommended posts: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_posts.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No recommendations yet. Interact more!'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const InterestPickerScreen()),
                );
              },
              child: const Text('Pick Interests'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadMorePosts(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _posts.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ));
          }
          final post = _posts[index];
          return PostCard(post: post);
        },
      ),
    );
  }
}
