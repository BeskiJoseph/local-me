import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geocoding_service.dart';
import '../services/user_service.dart';
import '../services/notification_data_service.dart';
import '../services/auth_service.dart';
import '../models/notification.dart';
import 'search_screen.dart';
import 'activity_screen.dart';
import 'personal_account.dart';
import 'community_screen.dart';
import 'post_type_selector_sheet.dart';
import '../widgets/home/home_feed_list.dart';
import '../widgets/bottom_nav_bar.dart';
import 'new_post_screen.dart';
import '../core/session/user_session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _currentCity;
  String? _currentCountry;
  bool _isLoadingLocation = true;
  String? _locationError;
  
  // Cache profile to avoid duplicate API calls
  dynamic _cachedProfile;

  // 0 = Nearby/Local, 1 = Global
  int _feedToggleIndex = 0;

  // Bottom nav: 0=Home, 1=Explore, 2=Create, 3=Groups, 4=Me
  int _bottomNavIndex = 0;

  // Incrementing forces HomeFeedList recreation → fresh feed fetch
  int _feedRevision = 0;

  @override
  void initState() {
    super.initState();
    _detectLocation();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      // Priority 1: Instant load from session or cached profile
      final userId = AuthService.currentUser?.uid;
      if (userId != null) {
        final session = UserSession.current.value;
        if (session != null && session.location != null && session.location!.isNotEmpty) {
           final parts = session.location!.split(',');
           if (mounted) {
            setState(() {
              _currentCity = parts[0].trim();
              if (parts.length > 1) _currentCountry = parts[1].trim();
              _isLoadingLocation = false;
            });
           }
        } else {
          _cachedProfile = await UserService.getUserProfile(userId);
          if (_cachedProfile?.location != null && _cachedProfile!.location!.isNotEmpty) {
            final parts = _cachedProfile.location!.split(',');
            if (mounted) {
              setState(() {
                _currentCity = parts[0].trim();
                if (parts.length > 1) _currentCountry = parts[1].trim();
                _isLoadingLocation = false; // Allow feed to start loading with cached location
              });
            }
            // Sync cached profile location to session for other screens
            UserSession.update(id: userId, location: _cachedProfile.location);
          }
        }
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Location services are disabled.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _isLoadingLocation = false;
            _locationError = 'Location permissions are denied.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Location permissions are permanently denied.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final place = await GeocodingService.getPlace(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _currentCity = place['city'] ?? 'Unknown City';
        _currentCountry = place['country'] ?? 'Unknown Country';
        _isLoadingLocation = false;
      });

      // Sync to backend profile AND session to avoid redundant requests in other screens (like "Me")
      if (userId != null && _currentCity != null) {
        final locationStr = _currentCountry != null 
            ? '$_currentCity, $_currentCountry' 
            : _currentCity!;
        
        // Update session immediately so other screens can access location without waiting
        UserSession.update(id: userId, location: locationStr);
            
        // Optimization: Only update if different from cached profile location
        final cachedLocation = _cachedProfile?.location;
        if (cachedLocation != locationStr) {
          UserService.updateUserProfile(
            userId: userId,
            location: locationStr,
          ).catchError((e) => debugPrint('Silent error syncing location: $e'));
        }
      }
    } catch (e) {
      debugPrint('Error detecting location: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _onNavTap(int index) {
    // Index 2 is now the dedicated Create button
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewPostScreen()),
      ).then((result) {
        if (result == true) {
          _refreshFeeds();
        }
      });
      return;
    }
    setState(() => _bottomNavIndex = index);
  }

  void _refreshFeeds() {
    setState(() => _feedRevision++);
  }



  Widget _buildHomeTab() {
    return Column(
      children: [
        // ── AppBar ─────────────────────────────────────────
        _HomeAppBar(
          feedToggleIndex: _feedToggleIndex,
          onToggleChanged: (i) => setState(() => _feedToggleIndex = i),
          onNotificationTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ActivityScreen()),
          ),
        ),
        // ── Feed ───────────────────────────────────────────
        Expanded(
          child: IndexedStack(
            index: _feedToggleIndex,
            children: [
              HomeFeedList(
                key: ValueKey('nearby_$_feedRevision'),
                feedType: 'local',
                userCity: _currentCity,
                userCountry: _currentCountry,
                isLoadingLocation: _isLoadingLocation,
                locationError: _locationError,
                onRetryLocation: _detectLocation,
                searchQuery: '',
              ),
              HomeFeedList(
                key: ValueKey('global_$_feedRevision'),
                feedType: 'global',
                userCity: _currentCity,
                userCountry: _currentCountry,
                isLoadingLocation: _isLoadingLocation,
                locationError: _locationError,
                onRetryLocation: _detectLocation,
                searchQuery: '',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _bottomNavIndex,
          children: [
            _buildHomeTab(),           // Index 0: Home
            const SearchScreen(),      // Index 1: Explore
            const SizedBox.shrink(),   // Index 2: Placeholder for Create (modal)
            CommunityScreen(),         // Index 3: Groups
            PersonalAccount(),         // Index 4: Me
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _bottomNavIndex,
        onTap: _onNavTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Home AppBar: Nearby/Global toggle + notification bell
// Pixel-matched to screenshot
// ─────────────────────────────────────────────────────────────
class _HomeAppBar extends StatelessWidget {
  final int feedToggleIndex;
  final ValueChanged<int> onToggleChanged;
  final VoidCallback onNotificationTap;

  const _HomeAppBar({
    required this.feedToggleIndex,
    required this.onToggleChanged,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // White background matching screenshot
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          // ── Nearby | Global pill toggle ──────────────────────
          _FeedToggle(
            selectedIndex: feedToggleIndex,
            onChanged: onToggleChanged,
          ),
          const Spacer(),
          // ── Notification bell + red badge ────────────────────
          GestureDetector(
            onTap: onNotificationTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.notifications_outlined,
                    color: Color(0xFF1A1A1A),
                    size: 26,
                  ),
                ),
                // Dynamic notification badge from stream - cached to avoid rebuilds
                const _NotificationBadge(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Nearby | Global pill toggle — matches screenshot exactly:
// Selected = green filled pill with white text
// Unselected = plain text, no background
// ─────────────────────────────────────────────────────────────
class _FeedToggle extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _FeedToggle({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleItem(
          label: 'Nearby',
          isSelected: selectedIndex == 0,
          onTap: () => onChanged(0),
        ),
        const SizedBox(width: 4),
        _ToggleItem(
          label: 'Global',
          isSelected: selectedIndex == 1,
          onTap: () => onChanged(1),
        ),
      ],
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
          ),
        ),
      ),
    );
  }
}

// Extracted widget to prevent stream recreation on parent rebuild
class _NotificationBadge extends StatefulWidget {
  const _NotificationBadge();

  @override
  State<_NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<_NotificationBadge> {
  late final Stream<List<ActivityNotification>> _notificationsStream;

  @override
  void initState() {
    super.initState();
    final userId = AuthService.currentUser?.uid ?? '';
    _notificationsStream = NotificationDataService.notificationsStream(userId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityNotification>>(
      stream: _notificationsStream,
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => !n.isRead).length;
        if (unreadCount == 0) return const SizedBox.shrink();
        return Positioned(
          top: 4,
          right: 4,
          child: Container(
            width: 17,
            height: 17,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppTheme.fontFamily,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
