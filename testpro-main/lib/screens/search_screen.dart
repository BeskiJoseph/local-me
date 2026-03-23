import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/backend_service.dart';
import '../services/auth_service.dart';
import '../services/search_service.dart';
import '../widgets/user_search_card.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import '../models/post.dart';
import '../utils/proxy_helper.dart';
import '../models/api_response.dart';
import 'post_reels_view.dart';
import '../services/post_service.dart';
import 'package:testpro/core/events/feed_events.dart';

/// Simple search screen with user and content search
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  
  Timer? _debounce;
  List<dynamic> _userResults = [];
  List<dynamic> _postResults = [];
  bool _isSearching = false;
  final Map<String, bool> _likedPostIds = {};
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _eventSubscription = FeedEventBus.events.listen((event) {
      if (event.type == FeedEventType.postLiked && mounted) {
        final data = event.data as Map<String, dynamic>;
        setState(() {
          _likedPostIds[data['postId']] = data['isLiked'];
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _debounce?.cancel();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _userResults = [];
        _postResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      
      setState(() {
        _searchQuery = query.trim();
        _isSearching = true;
      });

      try {
        // Single API call for both users and posts
        final results = await SearchService.searchAll(_searchQuery);
        
        if (mounted) {
          setState(() {
            _userResults = results['users'] ?? [];
            _postResults = results['posts'] ?? [];
            for (var p in _postResults) {
              if (p is Map<String, dynamic>) {
                _likedPostIds[p['id'] ?? p['postId'] ?? ''] = p['isLiked'] == true;
              }
            }
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Search',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Simple Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Search users or posts...',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade500,
                ),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500, size: 24),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
              ),
            ),
          ),

          // Tab Bar (only show when searching)
          if (_searchQuery.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Theme.of(context).textTheme.bodyMedium?.color,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: 'Inter',
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  fontFamily: 'Inter',
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person, size: 16),
                        SizedBox(width: 8),
                        Text('Users'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.article, size: 16),
                        SizedBox(width: 8),
                        Text('Posts'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Search Results
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildExploreGrid()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildUserSearch(),
                      _buildContentSearch(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSearch() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userResults.isEmpty) {
      return _buildNoResultsState('users');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _userResults.length,
      itemBuilder: (context, index) {
        final user = _userResults[index] as Map<String, dynamic>;
        return UserSearchCard(
          userId: user['id'] ?? user['uid'] ?? '',
          userData: user,
        );
      },
    );
  }

  Widget _buildContentSearch() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_postResults.isEmpty) {
      return _buildNoResultsState('posts');
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
      itemCount: _postResults.length,
      itemBuilder: (context, index) {
        final json = _postResults[index] as Map<String, dynamic>;
        final post = Post.fromJson(json);
        return NextdoorStylePostCard(
          post: post,
          initialIsLiked: _likedPostIds[post.id],
        );
      },
    );
  }

  Widget _buildExploreGrid() {
    final user = AuthService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<ApiResponse<List<dynamic>>>(
      future: BackendService.getPosts(feedType: 'global', limit: 30),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final response = snapshot.data;
        if (response == null || !response.success || response.data == null) return _buildEmptyState();

        final data = response.data!;
        final List<Post> allPosts = data.map((json) => Post.fromJson(json as Map<String, dynamic>)).toList();
        
        // Explore: Show only Image/Video posts (no Events, no Articles)
        final posts = allPosts.where((post) {
          // Skip events
          if (post.isEvent) return false;
          // Show all other posts, including text-only articles
          return true;
        }).toList();
        
        if (posts.isEmpty) return _buildEmptyState();

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 0.8, // Slightly taller for reels/images
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostReelsView(
                      posts: posts, 
                      startIndex: index,
                    ),
                  ),
                );
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (post.mediaUrl != null)
                    CachedNetworkImage(
                      imageUrl: ProxyHelper.getUrl(post.thumbnailUrl ?? post.mediaUrl!),
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (context, url) => Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 1, color: Colors.grey),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(Icons.error_outline, color: Colors.grey, size: 20),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: Colors.grey.shade100,
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: Text(
                          post.title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  if (post.mediaType == 'video')
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: Icon(Icons.play_circle_outline, color: Colors.white, size: 20),
                    ),
                  // Title overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 24),
          const Text(
            'Search Users \u0026 Posts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start typing to find what you\'re looking for',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(String type) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            type == 'users' ? Icons.person_off_outlined : Icons.article_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No $type found',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a different search term',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please try again',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              fontFamily: 'Inter',
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
