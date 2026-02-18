import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../widgets/post_card.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import 'edit_profile.dart';
import '../core/utils/format_utils.dart';
import '../shared/widgets/user_avatar.dart';

/// Threads-style profile screen
class PersonalAccount extends StatefulWidget {
  final String? userId;

  const PersonalAccount({super.key, this.userId});

  @override
  State<PersonalAccount> createState() => _PersonalAccountState();
}

class _PersonalAccountState extends State<PersonalAccount> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFollowing = false;
  bool _isLoading = false;

  String get profileUserId => widget.userId ?? FirebaseAuth.instance.currentUser!.uid;
  bool get isOwnProfile => widget.userId == null || widget.userId == FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (!isOwnProfile) {
      _checkIfFollowing();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkIfFollowing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirestoreService.isUserFollowedStream(user.uid, profileUserId).listen((following) {
      if (mounted) {
        setState(() {
          _isFollowing = following;
        });
      }
    });
  }

  Future<void> _toggleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await BackendService.toggleFollow(profileUserId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StreamBuilder<UserProfile?>(
        stream: FirestoreService.userProfileStream(profileUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.connectionState == ConnectionState.active && (snapshot.data == null)) {
            if (!isOwnProfile) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'User not found',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The requested profile does not exist.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }
            // If it's own profile but missing doc, we continue and let _buildNewProfileHeader handle fallback
          }

          final profile = snapshot.data;

          return CustomScrollView(
            slivers: [
              // Threads-style App Bar
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
                  onPressed: () => Navigator.of(context).canPop() ? Navigator.pop(context) : null,
                ),
                title: Text(
                  profile?.username ?? FirebaseAuth.instance.currentUser?.displayName ?? 'User',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),
                centerTitle: true,
                actions: [
                  if (isOwnProfile)
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.black),
                      onPressed: _signOut,
                    ),
                ],
              ),

              // Profile Content
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _buildNewProfileHeader(profile),
                    const Divider(height: 1),
                    _buildTabBar(),
                  ],
                ),
              ),

              // Tab Content
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPostsGrid(),
                    _buildFavoritesTab(),
                    _buildFollowersTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThreadsStat(String count, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44, // Tab Height: 44px
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF2563EB), // Active Color
        unselectedLabelColor: const Color(0xFF9CA3AF), // Inactive Color
        indicatorColor: const Color(0xFF2563EB), // Indicator Color
        indicatorWeight: 2, // Height 2px
        indicatorSize: TabBarIndicatorSize.tab, // Full width of tab? "No pill background" implies line.
        // Spec says "Radius: 2px", default indicator is square used to be.
        // We can use a custom decoration or shape if needed, but standard underline with weight 2 is close.
        dividerColor: Colors.transparent, // Clean look
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600, // Active Weight: 600
          fontSize: 14, // Size: 14px
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w500, // Inactive Weight: 500
          fontSize: 14, // Size: 14px
        ),
        tabs: const [
          Tab(text: "Posts"),
          Tab(text: "Favorites"),
          Tab(text: "Followers"),
        ],
      ),
    );
  }

  Widget _buildPostsGrid() {
    return StreamBuilder<List<Post>>(
      stream: FirestoreService.postsByAuthor(profileUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.post_add_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: AppTheme.spacing16),
                Text(
                  'Create your first post',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.spacing8),
                Text(
                  'Share your point of view.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: AppTheme.spacing24),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Create'),
                ),
              ],
            ),
          );
        }

        final posts = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8), // Minimal top padding
          physics: const NeverScrollableScrollPhysics(), // Scroll handled by CustomScrollView
          shrinkWrap: true, // Needed because it's inside CustomScrollView/SliverFillRemaining setup? 
          // Actually, if we use SliverChildBuilderDelegate inside a SliverList it would be better but we are in a TabBarView.
          // In TabBarView + CustomScrollView (pinned header), we ideally use NestedScrollView structure.
          // But with current structure (CustomScrollView -> SliverFillRemaining -> TabBarView -> ListView),
          // We need the ListView to NOT scroll itself but let the parent CustomScrollView handle it?
          // No, SliverFillRemaining makes the TabBarView take remaining space. The ListView INSIDE should scroll.
          // So physics: AlwaysScrollableScrollPhysics() or default.
          // But previously we had issues. 
          // However, the standard behavior for a tab view is to scroll.
          // Let's use default physics (remove physics: NeverScrollable...)
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return PostCard(post: post);
          },
        );
      },
    );
  }

  Widget _buildMediaGrid() {
    return StreamBuilder<List<Post>>(
      stream: FirestoreService.postsByAuthor(profileUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final posts = snapshot.data?.where((post) => post.mediaUrl != null).toList() ?? [];

        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: AppTheme.spacing16),
                Text(
                  'No media yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return GestureDetector(
              onTap: () {},
              child: Image.network(
                ProxyHelper.getUrl(post.mediaUrl!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey.shade800,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesTab() {
    return StreamBuilder<List<Post>>(
      stream: FirestoreService.likedPostsStream(profileUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final posts = snapshot.data ?? [];

        if (posts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text(
                  'No favorites yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            return PostCard(post: posts[index]);
          },
        );
      },
    );
  }

  Widget _buildFollowersTab() {
    // For now, simple empty state with design
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No followers yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share your profile to get discovered.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTab(String tabName) {
    return Center(
      child: Text(
        '$tabName coming soon',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey,
            ),
      ),
    );
  }

  Widget _buildNewProfileHeader(UserProfile? profile) {
    final authUser = FirebaseAuth.instance.currentUser;
    
    // Ensure username is not empty for display
    final String username;
    if (profile != null && profile.username.isNotEmpty) {
      username = profile.username;
    } else if (authUser?.displayName != null && authUser!.displayName!.isNotEmpty) {
      username = authUser.displayName!;
    } else {
      username = 'User';
    }

    final profileImage = profile?.profileImageUrl ?? authUser?.photoURL;
    final subscribers = profile?.subscribers ?? 0;
    final contents = profile?.contents ?? 0;

    return Padding(
      padding: const EdgeInsets.all(16), // Padding: 16px
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Profile Avatar: Size 72x72 (Radius 36), Margin Right 14
              Container(
                margin: const EdgeInsets.only(right: 14),
                child: UserAvatar(
                  imageUrl: profileImage,
                  name: username,
                  radius: 36,
                  initialsFontSize: 24,
                ),
              ),
              
              // Name & Stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username: 20px, Weight 600, Color #111827
                    Text(
                      username,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20, // Increased to 20px
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6), // Margin Top 6px
                    
                    // Stats Row
                    Row(
                      children: [
                        _buildStatItem('$contents', 'Posts'),
                        const SizedBox(width: 24), // Spacing increased to 24px
                        _buildStatItem(_formatCount(subscribers), 'Followers'),
                        const SizedBox(width: 24), // Spacing increased to 24px
                        _buildStatItem('180', 'Following'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Action Buttons
          if (isOwnProfile)
            SizedBox(
              width: double.infinity,
              height: 40, // Height 40px
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProfileScreen(profile: profile),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB), // Primary Blue
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Radius 12px
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  elevation: 0,
                ),
                child: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14, // Text 14px
                    fontWeight: FontWeight.w600, // Weight 600
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
             Row(
              children: [
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            onPressed: _toggleFollow,
                            style: ElevatedButton.styleFrom(
                               backgroundColor: _isFollowing ? Colors.grey[200] : const Color(0xFF2563EB),
                               foregroundColor: _isFollowing ? Colors.black : Colors.white,
                               elevation: 0,
                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                               padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              _isFollowing ? 'Following' : 'Follow',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'Message',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String count, String label) {
    return GestureDetector(
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 18, // Number 18px (was 16)
              fontWeight: FontWeight.w600, // Weight 600
              color: Color(0xFF111827),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12, // Label 12px
              fontWeight: FontWeight.w400, // Weight 400
              color: Color(0xFF6B7280), // Muted #6B7280
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) => FormatUtils.formatCount(count);
}
