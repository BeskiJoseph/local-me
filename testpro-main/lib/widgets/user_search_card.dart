import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../utils/proxy_helper.dart';
import '../screens/personal_account.dart';
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
  final FirestoreService _firestoreService = FirestoreService();
  bool _isFollowing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid == widget.userId) return;

    FirestoreService.isUserFollowedStream(user.uid, widget.userId).listen((following) {
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
      await BackendService.toggleFollow(widget.userId);
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

  void _navigateToProfile() {
    NavigationUtils.navigateToProfile(context, widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwnProfile = currentUser?.uid == widget.userId;

    final username = widget.userData['username'] ?? 'Unknown';
    final about = widget.userData['about'];
    final profileImage = widget.userData['profileImageUrl'];
    final subscribers = widget.userData['subscribers'] ?? 0;

    return Card(
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
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (about != null && about.isNotEmpty)
                      Text(
                        about,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      '$subscribers ${subscribers == 1 ? 'follower' : 'followers'}',
                      style: Theme.of(context).textTheme.bodySmall,
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: _toggleFollow,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing16,
                            vertical: AppTheme.spacing8,
                          ),
                          backgroundColor: _isFollowing
                              ? null
                              : Theme.of(context).colorScheme.primary,
                          foregroundColor: _isFollowing
                              ? null
                              : Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: Text(_isFollowing ? 'Following' : 'Follow'),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
