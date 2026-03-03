import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../core/utils/navigation_utils.dart';
import '../core/session/user_session.dart';
import 'edit_profile.dart';
import '../shared/widgets/user_avatar.dart';
import '../widgets/post_card.dart';
import '../widgets/nextdoor_post_card.dart';
import 'event_post_card.dart';
import '../services/post_service.dart';

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
  String? _profileError;
  bool _isLoadingPosts = false;
  String? _cursor;
  bool _hasMore = true;
  Map<String, bool> _likedPostIds = {};
  List<String> _myEventIds = [];
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  StreamSubscription? _eventSub;

  String get profileUserId {
    final uid = widget.userId ?? AuthService.currentUser?.uid;
    return uid ?? '';
  }

  // This getter is no longer used directly in build, but kept for other methods if needed.
  bool get isOwnProfile => widget.userId == null || widget.userId == AuthService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _eventSub = PostService.events.listen((event) {
      if (event.type == FeedEventType.postLiked && mounted) {
        final data = event.data as Map<String, dynamic>;
        setState(() {
          _likedPostIds[data['postId']] = data['isLiked'];
        });
      }
    });
  }

  @override
  void didUpdateWidget(PersonalAccount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (profileUserId.isEmpty) return;
    
    // Load profile header first for better perceived performance
    _loadProfile();
    
    // Then load other sections in parallel without blocking the UI
    _loadFollowState();
    _loadPosts(refresh: true);
    _loadMyEvents();
  }

  Future<void> _loadMyEvents() async {
    try {
      final response = await BackendService.getMyEventIds();
      if (response.success && response.data != null && mounted) {
        setState(() => _myEventIds = response.data!);
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });
    try {
      final response = await BackendService.getProfile(profileUserId);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _profile = UserProfile.fromJson(response.data!);
          _isLoadingProfile = false;
          _profileError = null;
        });
      } else {
        setState(() {
          _isLoadingProfile = false;
          _profileError = response.error ?? 'Failed to load profile';
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
          _profileError = 'Failed to load profile';
        });
      }
    }
  }

  Future<void> _loadFollowState() async {
    final user = AuthService.currentUser;
    if (user == null || isOwnProfile) return;
    try {
      final response = await BackendService.checkFollowState(profileUserId);
      if (response.success && mounted) {
        setState(() => _isFollowing = response.data ?? false);
      }
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_isTogglingFollow) return;
    setState(() => _isTogglingFollow = true);
    
    final originalState = _isFollowing;
    setState(() => _isFollowing = !originalState);

    try {
      final response = await BackendService.toggleFollow(profileUserId);
      if (!response.success && mounted) {
        setState(() => _isFollowing = originalState);
      }
    } catch (e) {
      if (mounted) setState(() => _isFollowing = originalState);
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
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

        // ── Optimized: Use Embedded isLiked ──
        setState(() {
          for (var p in newPosts) {
            _likedPostIds[p.id] = p.isLiked;
          }
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
      if (kDebugMode) debugPrint('Error loading profile posts: $e');
      if (mounted) setState(() => _isLoadingPosts = false);
    }
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

    if (!_isLoadingProfile && _profile == null && _profileError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _profileError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadProfile,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final user = AuthService.currentUser;
    final isOwnProfile = user != null && profileUserId == user.uid;
    return ValueListenableBuilder(
      valueListenable: UserSession.current,
      builder: (context, sessionData, _) {
        // Use fresh _profile data inside builder to ensure updates are reflected
        final profile = _profile;
        
        String fullNameFromProfile(UserProfile? p) {
          if (p == null) return '';
          final first = (p.firstName ?? '').trim();
          final last = (p.lastName ?? '').trim();
          return [first, last].where((v) => v.isNotEmpty).join(' ').trim();
        }

        String displayTitle = 'User';
        if (isOwnProfile) {
          // Priority: Session (real-time) > Firebase Auth > Backend Profile
          if (sessionData?.displayName != null && sessionData!.displayName!.isNotEmpty) {
            displayTitle = sessionData.displayName!;
          } else if (user?.displayName != null && user!.displayName!.isNotEmpty) {
            displayTitle = user.displayName!;
          } else if (profile != null && (profile.displayName ?? '').isNotEmpty) {
            displayTitle = profile.displayName!;
          } else if (profile != null && profile.username.isNotEmpty && profile.username != 'User') {
            displayTitle = profile.username;
          } else if (fullNameFromProfile(profile).isNotEmpty) {
            displayTitle = fullNameFromProfile(profile);
          } else if (user?.email != null) {
            displayTitle = user!.email!.split('@')[0];
          }
        } else {
          // STRICT SEPARATION: Only rely on fetched backend data for other users
          if (profile != null && (profile.displayName ?? '').isNotEmpty) {
            displayTitle = profile.displayName!;
          } else if (profile != null && profile.username.isNotEmpty && profile.username != 'User') {
            displayTitle = profile.username;
          } else if (fullNameFromProfile(profile).isNotEmpty) {
            displayTitle = fullNameFromProfile(profile);
          }
        }

        final String? profileImage = isOwnProfile 
            ? (sessionData?.avatarUrl ?? user?.photoURL ?? profile?.profileImageUrl) 
            : profile?.profileImageUrl;

        String displayLocation = 'Location not set';
        if (isOwnProfile) {
          displayLocation = sessionData?.location ?? profile?.location ?? 'Location not set';
        } else {
          displayLocation = profile?.location ?? 'Location not set';
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FA),
          body: RefreshIndicator(
            onRefresh: _loadData,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
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
                              name: displayTitle,
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
                          displayTitle,
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
                          displayLocation,
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

                    // Profile Actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: isOwnProfile
                          ? Row(
                              children: [
                                Expanded(
                                  child: _ActionBtn(
                                    label: 'Edit profile',
                                    color: const Color(0xFF2E7D6A),
                                    isOutlined: false,
                                    onTap: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditProfileScreen(profile: profile),
                                        ),
                                      );
                                      if (result == true) _loadData();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Stats integrated into a compact row
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFEEEEEE)),
                                  ),
                                  child: Row(
                                    children: [
                                      _buildStatItem('${profile?.subscribers ?? 0}', 'Followers'),
                                      const SizedBox(width: 16),
                                      _buildVerticalDivider(),
                                      const SizedBox(width: 16),
                                      _buildStatItem('${profile?.followingCount ?? 0}', 'Following'),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: _ActionBtn(
                                    label: _isFollowing ? 'Following' : 'Follow',
                                    color: _isFollowing ? Colors.grey.shade300 : const Color(0xFF2E7D6A),
                                    isOutlined: _isFollowing,
                                    onTap: _toggleFollow,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Stats for other user
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFEEEEEE)),
                                  ),
                                  child: Row(
                                    children: [
                                      _buildStatItem('${profile?.subscribers ?? 0}', 'Followers'),
                                      const SizedBox(width: 16),
                                      _buildVerticalDivider(),
                                      const SizedBox(width: 16),
                                      _buildStatItem('${profile?.followingCount ?? 0}', 'Following'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
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
    });
  }

  Widget _buildPostsTab() {
    final postOnlyItems = _posts.where((p) {
      final category = p.category.toLowerCase();
      final isArticle = category == 'article' || category == 'artizone';
      final isEvent = p.isEvent || category == 'events';
      final hasVisualMedia = p.mediaType == 'image' || p.mediaType == 'video';
      return !isArticle && !isEvent && hasVisualMedia;
    }).toList();

    if (postOnlyItems.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No photo/video posts yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: postOnlyItems.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == postOnlyItems.length) {
          if (!_isLoadingPosts && _hasMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadPosts();
            });
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final post = postOnlyItems[index];
        return NextdoorStylePostCard(
          post: post,
          initialIsLiked: _likedPostIds[post.id],
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
    final mediaPosts = _posts.where((p) {
      final category = p.category.toLowerCase();
      return category == 'article' || category == 'artizone';
    }).toList();
    if (mediaPosts.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No article posts yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: mediaPosts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == mediaPosts.length) {
          if (!_isLoadingPosts && _hasMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadPosts();
            });
          }
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
    final eventPosts = _posts
        .where((p) => p.isEvent || p.category.toLowerCase() == 'events')
        .toList();
    if (eventPosts.isEmpty && !_isLoadingPosts) {
      return const Center(child: Text('No events yet'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: eventPosts.length,
      itemBuilder: (context, index) {
        return EventPostCard(post: eventPosts[index]);
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
              color: color.withValues(alpha: 0.2),
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
  bool shouldRebuild(_SliverTabHeaderDelegate oldDelegate) => false;
}
