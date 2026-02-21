import 'package:flutter/material.dart';
import '../widgets/bottom_nav_bar.dart';
import 'feed_screen.dart';
import 'search_screen.dart';
import 'personal_account.dart';
import 'community_screen.dart';
import 'new_post_screen.dart';
import '../services/location_service.dart';

/// Main navigation container with bottom nav bar
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Centrally detect location once on app start
    LocationService.detectLocation();
  }

  void _onTabTapped(int index) {
    if (index == 2) {
      // Create button always opens the NewPostScreen modal
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NewPostScreen()),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  Widget _buildScreen() {
    switch (_currentIndex) {
      case 0:
        return const FeedScreen();
      case 1:
        return const SearchScreen();
      case 3:
        return CommunityScreen();
      case 4:
        return PersonalAccount();
      default:
        return const FeedScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex > 2 ? _currentIndex - 1 : _currentIndex,
        children: [
          const FeedScreen(),
          const SearchScreen(),
          CommunityScreen(),
          PersonalAccount(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}
