import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/post_service.dart';
import '../config/app_theme.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geocoding_service.dart';
import '../services/user_service.dart';
import '../services/notification_data_service.dart';
import '../services/auth_service.dart';
import 'search_screen.dart';
import 'activity_screen.dart';
import 'personal_account.dart';
import 'community_screen.dart';
import '../widgets/feed/paginated_feed_list.dart';
import '../widgets/feed/feed_shimmer.dart';
import '../widgets/bottom_nav_bar.dart';
import 'new_post_screen.dart';
import '../core/session/user_session.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/services/location_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:testpro/core/state/post_state.dart';
import '../utils/safe_error.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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

  final Set<int> _visitedNavIndexes = {0};
  final Set<int> _visitedFeedIndexes = {0};

  // Incrementing forces HomeFeedList recreation → fresh feed fetch
  int _feedRevision = 0;

  @override
  void initState() {
    // Activate custom backend session layer (bridging Firebase Auth)
    BackendService.syncCustomTokens();
    _initApp();
    // Fetch initial notification badge count (fire-and-forget)
    NotificationDataService.fetchNotifications();
  }

  Future<void> _initApp() async {
    try {
      await LocationService.detectLocation(forceSync: true);
      if (mounted) {
        setState(() {
           _currentCity = LocationService.currentCity;
           _currentCountry = LocationService.currentCountry;
           _isLoadingLocation = false;
        });
        ref.read(postStoreProvider.notifier).loadMore(feedType: 'local');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error initializing app location: $e');
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }


  Future<void> _refreshFeeds() async {
    if (kDebugMode) debugPrint('🔄 Refreshing feeds, revision: $_feedRevision -> ${_feedRevision + 1}');
    
    // Clear the store's cursors and seen IDs for a fresh start on refresh
    ref.read(postStoreProvider.notifier).clearSeen();
    
    setState(() {
      _feedRevision++;
    });
  }

  void _onNavTap(int index) {
    // Index 2 is now the dedicated Create button
    if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewPostScreen()),
      ).then((result) async {
        if (result == true) {
          if (kDebugMode) debugPrint('📝 Post creation confirmed, triggering feed refresh');
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) {
            _refreshFeeds();
          }
        }
      });
      return;
    }
    setState(() {
      _bottomNavIndex = index;
      _visitedNavIndexes.add(index);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _refreshFeedsInternal() {
    _refreshFeeds();
  }



  Widget _buildHomeTab() {
    return Column(
      children: [
        // ── AppBar ─────────────────────────────────────────
        _HomeAppBar(
          feedToggleIndex: _feedToggleIndex,
          onToggleChanged: (i) => setState(() {
            _feedToggleIndex = i;
            _visitedFeedIndexes.add(i);
            if (i == 1 && _visitedFeedIndexes.length == 2) {
                ref.read(postStoreProvider.notifier).loadMore(feedType: 'global');
            }
          }),
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
              _isLoadingLocation
                  ? const FeedShimmer(itemCount: 3)
                  : _locationError != null
                      ? _LocationErrorState(
                          error: _locationError!,
                          onRetry: _initApp,
                        )
                      : PaginatedFeedList(
                          key: ValueKey('nearby_$_feedRevision'),
                          feedType: 'local',
                          userCity: _currentCity,
                          userCountry: _currentCountry,
                          onRefresh: _refreshFeeds,
                        ),
              _visitedFeedIndexes.contains(1)
                  ? PaginatedFeedList(
                      key: ValueKey('global_$_feedRevision'),
                      feedType: 'global',
                      onRefresh: _refreshFeeds,
                    )
                  : const SizedBox.shrink(),
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
            _visitedNavIndexes.contains(0) ? _buildHomeTab() : const SizedBox.shrink(),           // Index 0: Home
            _visitedNavIndexes.contains(1) ? const SearchScreen() : const SizedBox.shrink(),      // Index 1: Explore
            const SizedBox.shrink(),   // Index 2: Placeholder for Create (modal)
            _visitedNavIndexes.contains(3) ? CommunityScreen() : const SizedBox.shrink(),         // Index 3: Groups
            _visitedNavIndexes.contains(4) ? PersonalAccount() : const SizedBox.shrink(),         // Index 4: Me
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
class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationDataService.unreadCount,
      builder: (context, unreadCount, child) {
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
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}



// ─────────────────────────────────────────────────────────────
// Location Error State — cleaner UX
// ─────────────────────────────────────────────────────────────
class _LocationErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _LocationErrorState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 36,
                color: Color(0xFFFF9800),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Can\'t find your location',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                color: Color(0xFF8A8A8A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
