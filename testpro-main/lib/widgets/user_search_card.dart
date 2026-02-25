import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../services/auth_service.dart';
import '../shared/widgets/user_avatar.dart';
import '../core/utils/navigation_utils.dart';

/// User search card for search results
class UserSearchCard extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> userData;

  const UserSearchCard({
    super.key,
    required this.userId,
    required this.userData,
  });

  @override
  State<UserSearchCard> createState() => _UserSearchCardState();
}

class _UserSearchCardState extends State<UserSearchCard> {
  bool _isFollowing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    final user = AuthService.currentUser;
    if (user == null || user.uid == widget.userId) return;

    try {
      final response = await BackendService.checkFollowState(widget.userId);
      if (mounted && response.success) {
        setState(() {
          _isFollowing = response.data ?? false;
        });
      }
    } catch (e) {
      debugPrint('Error checking follow state: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final user = AuthService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isFollowing = !_isFollowing; // Optimistic update
    });

    try {
      final response = await BackendService.toggleFollow(widget.userId);
      // Trust the toggle response, no need for second API call
      if (mounted && response.success) {
        setState(() {
          _isFollowing = response.data ?? !_isFollowing;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing; // Revert on error
        });
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

  void _navigateToProfile() {
    NavigationUtils.navigateToProfile(context, widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService.currentUser;
    final isOwnProfile = currentUser?.uid == widget.userId;

    final username = widget.userData['displayName'] ?? widget.userData['username'] ?? 'Unknown';
    final about = widget.userData['about'];
    final profileImage = widget.userData['profileImageUrl'];
    final subscribers = widget.userData['subscribers'] ?? 0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: const BorderSide(color: Color(0xFFF2F2F2)),
      ),
      child: InkWell(
        onTap: _navigateToProfile,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing16),
          child: Row(
            children: [
              // Avatar
              UserAvatar(
                imageUrl: profileImage,
                name: username,
                radius: 28,
                initialsFontSize: 24,
              ),
              const SizedBox(width: AppTheme.spacing16),

              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (about != null && about.isNotEmpty)
                      Text(
                        about,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 14,
                          color: Color(0xFF8A8A8A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      '$subscribers ${subscribers == 1 ? 'follower' : 'followers'}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: Color(0xFF8A8A8A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Follow button
              if (!isOwnProfile)
                _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                      )
                    : SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: _toggleFollow,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            backgroundColor: _isFollowing
                                ? Colors.transparent
                                : AppTheme.primary,
                            foregroundColor: _isFollowing
                                ? AppTheme.primary
                                : Colors.white,
                            side: BorderSide(
                              color: AppTheme.primary,
                              width: _isFollowing ? 1 : 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            _isFollowing ? 'Following' : 'Follow',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
