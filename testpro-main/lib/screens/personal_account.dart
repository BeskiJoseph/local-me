import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../models/paginated_response.dart';
import 'edit_profile.dart';
import '../shared/widgets/user_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/nextdoor_post_card.dart';

class PersonalAccount extends StatefulWidget {
  final String? userId;

  const PersonalAccount({super.key, this.userId});

  @override
  State<PersonalAccount> createState() => _PersonalAccountState();
}

class _PersonalAccountState extends State<PersonalAccount> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // REST States
  UserProfile? _profile;
  List<Post> _posts = [];
  bool _isLoadingProfile = true;
  bool _isLoadingPosts = false;
  String? _cursor;
  bool _hasMore = true;
  final Map<String, bool> _likedPostIds = {};

  String get profileUserId {
    final uid = widget.userId ?? AuthService.currentUser?.uid;
    return uid ?? '';
  }

  bool get isOwnProfile => widget.userId == null || widget.userId == AuthService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void didUpdateWidget(PersonalAccount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (profileUserId.isEmpty) return;
    await Future.wait([
      _loadProfile(),
      _loadPosts(refresh: true),
    ]);
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _isLoadingProfile = true);
    try {
      final response = await BackendService.getProfile(profileUserId);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _profile = UserProfile.fromJson(response.data!);
          _isLoadingProfile = false;
        });
      } else {
        setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoadingPosts) return;
    if (!refresh && !_hasMore) return;

    if (mounted) setState(() => _isLoadingPosts = true);

    try {
      final response = await BackendService.getPosts(
        authorId: profileUserId,
        afterId: refresh ? null : _cursor,
        limit: 10,
      );

      if (!mounted) return;

      if (response.success && response.data != null) {
        final List<dynamic> data = response.data!;
        final String? nextCursor = response.pagination?.cursor;
        final List<Post> newPosts = data.map((e) => Post.fromJson(e)).toList();

        // ── Batch Lookups (Prevent N+1) ──
        final List<String> postIds = newPosts.map((p) => p.id).toList();
        if (postIds.isNotEmpty) {
           BackendService.instance.getLikesBatch(postIds).then((likeResp) {
             if (mounted && likeResp.success && likeResp.data != null) {
                setState(() {
                  _likedPostIds.addAll(Map<String, bool>.from(likeResp.data!));
                });
             }
           });
        }
        setState(() {
          if (refresh) {
            _posts.clear();
          }
          _posts.addAll(newPosts);
          _cursor = nextCursor;
          _hasMore = nextCursor != null;
          _isLoadingPosts = false;
        });
      } else {
        setState(() => _isLoadingPosts = false);
      }
    } catch (e) {
      debugPrint('Error loading profile posts: $e');
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (profileUserId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view profile')),
      );
    }

    if (_isLoadingProfile && _profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile;
    final user = AuthService.currentUser;
    
    // Improved username logic with fallbacks
    String username = 'User';
    if (profile != null && profile.username.isNotEmpty && profile.username != 'User') {
      username = profile.username;
    } else if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      username = user.displayName!;
    } else if (user?.email != null) {
      username = user!.email!.split('@')[0];
    }

    final String? profileImage = profile?.profileImageUrl ?? (isOwnProfile ? user?.photoURL : null);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
              // ── Unified Profile Header (Banner + Avatar + Info) ──────────────────────────
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Banner (Shortened)
                        Container(
                          height: 100,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF2E7D6A),
                                Color(0xFF1A4D42),
                              ],
                            ),
                          ),
                        ),
                        // Back & Settings Icons
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Navigator.of(context).canPop()
                              ? IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: Icon(
                              isOwnProfile ? Icons.settings_outlined : Icons.more_horiz,
                              color: Colors.white,
                            ),
                            onPressed: () async {
                              if (isOwnProfile) {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditProfileScreen(profile: profile),
                                  ),
                                );
                                if (result == true) {
                                  _loadData();
                                }
                              }
                            },
                          ),
                        ),
                        // Overlapping Avatar (Ensured on top via Stack order)
                        Positioned(
                          bottom: -54, // Centered on the bottom edge (radius is 54)
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: UserAvatar(
                              imageUrl: profileImage,
                              name: username,
                              radius: 54,
                              initialsFontSize: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 54 + 16), // Padding for the overlapping avatar
                    // Username & Verification
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 28, // Slightly larger
                            fontWeight: FontWeight.w900, // Extra bold for "Beski" look
                            fontFamily: AppTheme.fontFamily,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                           padding: const EdgeInsets.all(2),
                           decoration: const BoxDecoration(color: Color(0xFF2E7D6A), shape: BoxShape.circle),
                           child: const Icon(Icons.check, color: Colors.white, size: 10),
                        ),
                      ],
                    ),

                    // Location
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Color(0xFF8A8A8A)),
                        const SizedBox(width: 4),
                        Text(
                          profile?.location ?? 'Location not set',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF8A8A8A),
                            fontFamily: AppTheme.fontFamily,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Bio (About us) - Positioned in between per user request
                    if (profile?.about != null && profile!.about!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          profile.about!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4A4A4A),
                            height: 1.4,
                            fontFamily: AppTheme.fontFamily,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Own Profile Actions (Matching the screenshot)
                    if (isOwnProfile)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: _ActionBtn(
                                label: 'Edit profile',
                                color: const Color(0xFF2E7D6A), // Teal like screenshot
                                isOutlined: false,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditProfileScreen(profile: profile),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ActionBtn(
                                label: '${profile?.followingCount ?? 0}', // Stats in button
                                icon: Icons.people_outline,
                                color: const Color(0xFF2E7D6A),
                                isOutlined: false,
                                onTap: () {},
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),

              // ── Sticky Tab Bar ─────────────────────────────────
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabHeaderDelegate(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: AppTheme.primary,
                      indicatorWeight: 2,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: const Color(0xFF1A1A1A),
                      unselectedLabelColor: const Color(0xFF8A8A8A),
                      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: AppTheme.fontFamily),
                      unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, fontFamily: AppTheme.fontFamily),
                      tabs: const [
                        Tab(text: "Posts"),
                        Tab(text: "ArtiZone"),
                        Tab(text: "Events"),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Posts List ─────────────────────────────────────
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPostsTab(),
                    _buildMediaGrid(),
                    _buildEventsTab(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsTab() {
    if (_posts.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No posts yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          _loadPosts();
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return NextdoorStylePostCard(
          post: _posts[index],
          initialIsLiked: _likedPostIds[_posts[index].id],
        );
      },
    );
  }

  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
            fontFamily: AppTheme.fontFamily,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8A8A8A),
            fontWeight: FontWeight.w500,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 20,
      width: 1,
      color: const Color(0xFFEEEEEE),
    );
  }

  Widget _buildMediaGrid() {
    final mediaPosts = _posts.where((p) => p.category == 'ArtiZone').toList();
    if (mediaPosts.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No ArtiZone posts yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: mediaPosts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == mediaPosts.length) {
          _loadPosts();
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        return NextdoorStylePostCard(
          post: mediaPosts[index],
          initialIsLiked: _likedPostIds[mediaPosts[index].id],
        );
      },
    );
  }

  Widget _buildEventsTab() {
    final eventPosts = _posts.where((p) => p.isEvent).toList();
    if (eventPosts.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No events yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: eventPosts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == eventPosts.length) {
          _loadPosts();
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        return NextdoorStylePostCard(
          post: eventPosts[index],
          initialIsLiked: _likedPostIds[eventPosts[index].id],
        );
      },
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool isOutlined;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    this.icon,
    required this.color,
    this.isOutlined = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38, // More compact height
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isOutlined ? const Color(0xFFEEEEEE) : color,
          borderRadius: BorderRadius.circular(10), // Slightly tighter radius
          boxShadow: isOutlined ? null : [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isOutlined ? const Color(0xFF1A1A1A) : Colors.white,
                fontSize: 14, // Smaller, sleeker font
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.fontFamily,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SliverTabHeaderDelegate({required this.child});

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverTabHeaderDelegate oldDelegate) => true;
}
