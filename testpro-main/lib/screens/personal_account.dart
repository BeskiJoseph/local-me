import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/auth_service.dart';
import '../services/backend_service.dart';
import '../config/app_theme.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../core/session/user_session.dart';
import 'edit_profile.dart';
import '../shared/widgets/user_avatar.dart';
import '../shared/widgets/empty_state.dart';
import 'package:testpro/widgets/nextdoor_post_card.dart';
import 'event_post_card.dart';
import 'post_reels_view.dart';
import '../services/interaction_service.dart';
import '../mixins/post_loader_mixin.dart';

class PersonalAccount extends ConsumerStatefulWidget {
  final String? userId;

  const PersonalAccount({super.key, this.userId});

  /// 🔥 Global key to access profile state from anywhere for adding new posts
  static final GlobalKey<_PersonalAccountState> profileKey = GlobalKey<_PersonalAccountState>();

  @override
  ConsumerState<PersonalAccount> createState() => _PersonalAccountState();
}

class _PersonalAccountState extends ConsumerState<PersonalAccount>
    with SingleTickerProviderStateMixin, PostLoaderMixin {
  late TabController _tabController;

  // REST States
  UserProfile? _profile;
  List<Post> _posts = [];
  bool _isLoadingProfile = true;
  String? _profileError;
  bool _isLoadingPosts = false;
  bool _hasMore = true;
  Map<String, bool> _likedPostIds = {};
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  String profileUserId = '';

  // PostLoaderMixin implementation
  @override
  List<Post> get posts => _posts;
  
  @override
  set posts(List<Post> value) => _posts = value;
  
  @override
  bool get isLoading => _isLoadingPosts;
  
  @override
  set isLoading(bool value) {
    if (mounted) setState(() => _isLoadingPosts = value);
  }
  
  @override
  bool get hasMore => _hasMore;
  
  @override
  set hasMore(bool value) => _hasMore = value;
  
  @override
  Map<String, bool> get likedPostIds => _likedPostIds;
  
  @override
  String? get authorId => profileUserId;

  // This getter is no longer used directly in build, but kept for other methods if needed.
  bool get isOwnProfile =>
      widget.userId == null || widget.userId == AuthService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    // Initialize profileUserId based on widget.userId or current user
    profileUserId = widget.userId ?? AuthService.currentUser?.uid ?? '';
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (profileUserId.isEmpty) return;

    // Load profile header first for better perceived performance
    _loadProfile();

    // Then load other sections in parallel without blocking the UI
    _loadFollowState();
    loadPosts(refresh: true);
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
    await InteractionService.toggleFollowUser(
      targetUserId: profileUserId,
      ref: ref,
      onBusy: () => setState(() => _isTogglingFollow = true),
      onReady: () => setState(() => _isTogglingFollow = false),
      onResult: (isFollowing) {
        setState(() {
          _isFollowing = isFollowing;
        });
      },
    );
  }

  /// 🔥 FIX: Add new post to the TOP of profile list immediately
  void addNewPost(Post post) {
    if (post.authorId != profileUserId) return;
    if (mounted) {
      setState(() {
        _posts.insert(0, post);
        _likedPostIds[post.id] = post.isLiked;
      });
    }
  }

  @override
  void onPostsError(dynamic error) {
    if (kDebugMode) debugPrint('Error loading profile posts: $error');
    showError(error);
  }

  @override
  Widget build(BuildContext context) {
    if (profileUserId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view profile')),
      );
    }

    if (_isLoadingProfile && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
          if (sessionData?.displayName != null &&
              sessionData!.displayName!.isNotEmpty) {
            displayTitle = sessionData.displayName!;
          } else if (user?.displayName != null &&
              user.displayName!.isNotEmpty) {
            displayTitle = user.displayName!;
          } else if (profile != null &&
              (profile.displayName ?? '').isNotEmpty) {
            displayTitle = profile.displayName!;
          } else if (profile != null &&
              profile.username.isNotEmpty &&
              profile.username != 'User') {
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
          } else if (profile != null &&
              profile.username.isNotEmpty &&
              profile.username != 'User') {
            displayTitle = profile.username;
          } else if (fullNameFromProfile(profile).isNotEmpty) {
            displayTitle = fullNameFromProfile(profile);
          }
        }

        final String? profileImage = isOwnProfile
            ? (sessionData?.avatarUrl ??
                  user?.photoURL ??
                  profile?.profileImageUrl)
            : profile?.profileImageUrl;

        String displayLocation = 'Location not set';
        if (isOwnProfile) {
          displayLocation =
              sessionData?.location ?? profile?.location ?? 'Location not set';
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Use a Stack for the Banner and its overlays (Settings/Back)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Banner
                          Container(
                            height: 120,
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF2E7D6A), Color(0xFF1A4D42)],
                              ),
                            ),
                          ),
                          // Back Button
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Navigator.of(context).canPop()
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(context),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          // Settings Icon
                          Positioned(
                            top: 10,
                            right: 15,
                            child: IconButton(
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: Colors.white,
                                size: 28,
                              ),
                              onPressed: () async {
                                if (isOwnProfile) {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          EditProfileScreen(profile: profile),
                                    ),
                                  );
                                  if (result == true) _loadData();
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      // Secondary Header Section: Avatar and Action Button
                      // This part is placed below the Stack but uses translation to overlap
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Overlapping Avatar
                            Transform.translate(
                              offset: const Offset(0, -45),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: GestureDetector(
                                  onTap: () async {
                                    if (isOwnProfile) {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              EditProfileScreen(
                                                profile: profile,
                                              ),
                                        ),
                                      );
                                      if (result == true) _loadData();
                                    }
                                  },
                                  child: UserAvatar(
                                    imageUrl: profileImage,
                                    name: displayTitle,
                                    radius: 50,
                                    initialsFontSize: 36,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Action Button (Edit Profile / Follow)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 12,
                              ), // Space it above the name section
                              child: isOwnProfile
                                  ? OutlinedButton(
                                      onPressed: () async {
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                EditProfileScreen(
                                                  profile: profile,
                                                ),
                                          ),
                                        );
                                        if (result == true) _loadData();
                                      },
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0xFFCCCCCC),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 8,
                                        ),
                                      ),
                                      child: const Text(
                                        'Edit profile',
                                        style: TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          fontFamily: AppTheme.fontFamily,
                                        ),
                                      ),
                                    )
                                  : ElevatedButton(
                                      onPressed: _toggleFollow,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isFollowing
                                            ? Colors.grey.shade200
                                            : const Color(0xFF2E7D6A),
                                        foregroundColor: _isFollowing
                                            ? const Color(0xFF1A1A1A)
                                            : Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 8,
                                        ),
                                      ),
                                      child: Text(
                                        _isFollowing ? 'Following' : 'Follow',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),

                      // Adjust spacing before name
                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name & Verified Badge
                            Row(
                              children: [
                                Text(
                                  displayTitle,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: AppTheme.fontFamily,
                                    color: Color(0xFF1A1A1A),
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2E7D6A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Location
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 18,
                                  color: Color(0xFF666666),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  displayLocation,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF666666),
                                    fontFamily: AppTheme.fontFamily,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Bio
                            if (profile?.about != null &&
                                profile!.about!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  profile.about!,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF1A1A1A),
                                    height: 1.4,
                                    fontFamily: AppTheme.fontFamily,
                                  ),
                                ),
                              ),

                            // Stats line
                            Row(
                              children: [
                                Text(
                                  '${profile?.followingCount ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Following',
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '·',
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${profile?.subscribers ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Followers',
                                  style: TextStyle(
                                    color: Color(0xFF666666),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
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
                        border: Border(
                          bottom: BorderSide(
                            color: Color(0xFFEEEEEE),
                            width: 1,
                          ),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: AppTheme.primary,
                        indicatorWeight: 2,
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: const Color(0xFF1A1A1A),
                        unselectedLabelColor: const Color(0xFF8A8A8A),
                        labelStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTheme.fontFamily,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          fontFamily: AppTheme.fontFamily,
                        ),
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
      },
    );
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
      return const EmptyStateWidget(
        icon: Icons.photo_library_outlined,
        title: 'No photo/video posts yet',
        subtitle: 'Posts with images or videos will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: postOnlyItems.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == postOnlyItems.length) {
          if (!_isLoadingPosts && _hasMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadPosts();
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostReelsView(
                posts: postOnlyItems,
                startIndex: index,
                authorId: profileUserId,
                initialHasMore: _hasMore,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaGrid() {
    final mediaPosts = _posts.where((p) {
      final category = p.category.toLowerCase();
      return category == 'article' || category == 'artizone';
    }).toList();
    if (mediaPosts.isEmpty && !_isLoadingPosts) {
      return const EmptyStateWidget(
        icon: Icons.article_outlined,
        title: 'No articles yet',
        subtitle: 'Articles and stories you write will appear here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: mediaPosts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == mediaPosts.length) {
          if (!_isLoadingPosts && _hasMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadPosts();
            });
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final post = mediaPosts[index];
        return NextdoorStylePostCard(
          post: post,
          initialIsLiked: _likedPostIds[post.id],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostReelsView(
                posts: mediaPosts,
                startIndex: index,
                authorId: profileUserId,
                initialHasMore: _hasMore,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventsTab() {
    final eventPosts = _posts
        .where((p) => p.isEvent || p.category.toLowerCase() == 'events')
        .toList();
    if (eventPosts.isEmpty && !_isLoadingPosts) {
      return const EmptyStateWidget(
        icon: Icons.event_available_outlined,
        title: 'No events joined or created',
        subtitle: 'Events you are interested in will show up here.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: eventPosts.length,
      itemBuilder: (context, index) {
        return EventPostCard(
          post: eventPosts[index],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PostReelsView(
                posts: eventPosts,
                startIndex: index,
                authorId: profileUserId,
                initialHasMore: _hasMore,
              ),
            ),
          ),
        );
      },
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_SliverTabHeaderDelegate oldDelegate) => false;
}
