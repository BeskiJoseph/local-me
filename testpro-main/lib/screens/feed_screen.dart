import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/feed/paginated_feed_list.dart';
import '../services/location_service.dart';

/// Premium feed screen with Local and Global tabs
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
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
            Tab(text: 'Global'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      // IndexedStack keeps both tabs alive
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          const PaginatedFeedList(feedType: 'local'),
          const PaginatedFeedList(feedType: 'global'),
        ],
      ),
    );
  }
}
