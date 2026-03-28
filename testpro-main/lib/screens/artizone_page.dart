import 'package:flutter/material.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../shared/widgets/empty_state.dart';
import 'article_reading_screen.dart';
import 'create_article_screen.dart';

class ArtizonePage extends StatefulWidget {
  final String userId;

  const ArtizonePage({super.key, required this.userId});

  @override
  State<ArtizonePage> createState() => _ArtizonePageState();
}

class _ArtizonePageState extends State<ArtizonePage> {
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _hasMore = true;
  Map<String, bool> _likedPostIds = {};

  @override
  void initState() {
    super.initState();
    _loadPosts(refresh: true);
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (!refresh && !_hasMore) return;
    if (mounted && refresh) setState(() => _isLoading = true);

    try {
      final response = await PostService.getFilteredPostsPaginated(
        authorId: widget.userId,
        limit: 20,
      );

      if (!mounted) return;

      final List<Post> newPosts = response.data;

      setState(() {
        for (var p in newPosts) {
          _likedPostIds[p.id] = p.isLiked;
        }
        if (refresh) {
          _posts.clear();
        }
        _posts.addAll(newPosts);
        _hasMore = response.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPosts = _posts.where((p) {
      final category = p.category.toLowerCase();
      return category == 'article' || category == 'artizone';
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: RefreshIndicator(
        onRefresh: () => _loadPosts(refresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 180.0,
              pinned: true,
              backgroundColor: const Color(0xFF2E7D6A),
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                title: const Text(
                  'ArtiZone',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Abstract pattern or gradient background
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2E7D6A), Color(0xFF1B4E41)],
                        ),
                      ),
                    ),
                    const Positioned(
                      right: -30,
                      top: -20,
                      child: Icon(
                        Icons.article,
                        size: 150,
                        color: Colors.white10,
                      ),
                    ),
                    const Positioned(
                      left: 20,
                      bottom: 50,
                      child: Text(
                        'Discover articles & stories',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            if (_isLoading && _posts.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (mediaPosts.isEmpty)
              const SliverFillRemaining(
                child: EmptyStateWidget(
                  icon: Icons.article_outlined,
                  title: 'No articles yet',
                  subtitle: 'Articles and stories will appear here.',
                  iconSize: 80,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 0,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index == mediaPosts.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadPosts();
                      });
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final post = mediaPosts[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: NextdoorStylePostCard(
                        post: post,
                        initialIsLiked: _likedPostIds[post.id],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ArticleReadingScreen(article: post),
                          ),
                        ),
                      ),
                    );
                  }, childCount: mediaPosts.length + (_hasMore ? 1 : 0)),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateArticleScreen()),
          );
          if (result == true) {
            _loadPosts(refresh: true);
          }
        },
        backgroundColor: const Color(0xFF2E7D6A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_document),
        label: const Text('Write Article'),
      ),
    );
  }
}
