import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/feed/recommended_feed_list.dart';
import '../widgets/feed/paginated_feed_list.dart';

/// Premium feed screen with Local, National, Global tabs
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // In a real app, integrate location service. Using defaults for MVP/Demo.
  final String _userCity = "San Francisco";
  final String _userCountry = "USA";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Feed',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.eventGreen,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppTheme.eventGreen,
          tabs: const [
            Tab(text: 'Local'),
            Tab(text: 'National'),
            Tab(text: 'Global'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {
              // TODO: connect to search screen
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {
              // TODO: connect to notifications
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeedTab('local'),
          _buildFeedTab('national'),
          _buildFeedTab('global'),
        ],
      ),
    );
  }

  Widget _buildFeedTab(String feedType) {
    if (feedType == 'global') {
      return const RecommendedFeedList();
    }

    return PaginatedFeedList(
      feedType: feedType,
      userCity: _userCity,
      userCountry: _userCountry,
    );
  }
}
