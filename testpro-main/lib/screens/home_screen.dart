
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/post.dart';
import 'new_post_screen.dart';
import 'package:geolocator/geolocator.dart';
import '../services/geocoding_service.dart';
import '../utils/proxy_helper.dart';
import 'welcome_screen.dart';
import 'reels_feed_screen.dart';
import 'event_post_card.dart';
import 'search_screen.dart';
import 'post_detail_screen.dart';
import 'activity_screen.dart';
import 'package:flutter/rendering.dart';
import 'personal_account.dart';
import 'community_screen.dart';
import 'post_type_selector_sheet.dart';
import '../widgets/nextdoor_post_card.dart';
import '../widgets/home/home_feed_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  String? _currentCity;
  String? _currentCountry;
  bool _isLoadingLocation = true;
  String? _locationError;
  int _currentFeedIndex = 0;
  int _bottomNavIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  late PageController _pageController;
  late ScrollController _scrollController;
  bool _showFAB = true;

  // ADD THIS METHOD
  void _openReelsFeed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelsFeedScreen(
          feedType: _getCurrentFeedType(),
          userCity: _currentCity,
          userCountry: _currentCountry,
        ),
      ),
    );
  }

  // ADD THIS METHOD
  String _getCurrentFeedType() {
    switch (_currentFeedIndex) {
      case 0:
        return 'local';
      case 1:
        return 'national';
      case 2:
        return 'global';
      default:
        return 'local';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController(initialPage: 0);
    _scrollController = ScrollController();
    
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_showFAB) setState(() => _showFAB = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_showFAB) setState(() => _showFAB = true);
      }
    });

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
    _detectLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
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
          _locationError =
              'Location permissions are permanently denied. Please enable them in your browser/device settings.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      
      final place = await GeocodingService.getPlace(
        position.latitude, 
        position.longitude
      );

      if (!mounted) return;

      if (place['city'] != null || place['country'] != null) {
        setState(() {
          _currentCity = place['city'];
          _currentCountry = place['country'];
          _isLoadingLocation = false;
        });
      } else {
        setState(() {
          _currentCity = 'Unknown City';
          _currentCountry = 'Unknown Country';
          _isLoadingLocation = false;
        });
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

  Future<void> _logout() async {
    await AuthService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    if (_bottomNavIndex != 0) {
      return Scaffold(
        body: _bottomNavIndex == 1
            ? const SearchScreen()
            : _bottomNavIndex == 2
                ? CommunityScreen()
                : _bottomNavIndex == 3
                    ? PersonalAccount() // Renamed from ProfileScreen in some contexts?
                    : const Center(
                        child: Text('Other Screen'),
                      ),
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButton: AnimatedScale(
          scale: _showFAB ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeIn,
          child: _buildFAB(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00B87C),
          indicatorWeight: 3,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamily: 'Inter',
          ),
          tabs: const [
            Tab(text: 'Local'),
            Tab(text: 'Global'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivityScreen()),
              );
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentFeedIndex = index;
            _tabController.animateTo(index);
          });
        },
        children: [
            HomeFeedList(
              feedType: 'national', // "Local" tab mapped to national for now
              userCity: _currentCity,
              userCountry: _currentCountry,
              isLoadingLocation: _isLoadingLocation,
              locationError: _locationError,
              onRetryLocation: _detectLocation,
              searchQuery: _searchQuery,
              scrollController: _scrollController,
            ),
            HomeFeedList(
              feedType: 'global',
              userCity: _currentCity,
              userCountry: _currentCountry,
              isLoadingLocation: _isLoadingLocation,
              locationError: _locationError,
              onRetryLocation: _detectLocation,
              searchQuery: _searchQuery,
              scrollController: _scrollController,
            ),
        ],
      ),
      floatingActionButton: AnimatedScale(
        scale: _showFAB ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeIn,
        child: _buildFAB(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => const PostTypeSelectorSheet(),
        );
      },
      backgroundColor: const Color(0xFF00B87C),
      child: const Icon(Icons.add, size: 32),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 8,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 'Feed', 0),
            _buildNavItem(Icons.explore_outlined, 'Explore', 1),
            const SizedBox(width: 40),
            _buildNavItem(Icons.groups_3_outlined, 'Community', 2),
            _buildNavItem(Icons.person_outline, 'Profile', 3),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _bottomNavIndex == index;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _bottomNavIndex = index;
          });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00B87C) : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00B87C) : Colors.grey.shade600,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
