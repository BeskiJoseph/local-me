import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../components/paginated_feed.dart';
import '../controllers/feed_controller.dart';

/// The entry point for the new core_feed module.
/// 🥈 Phase 7.2: Handles switching between Discovery (Home) and Global feeds.
class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.teal,
                indicatorWeight: 3,
                labelColor: Colors.black,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(text: "Nearby"),
                  Tab(text: "Global"),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Discovery Engine (nearby-first)
          PaginatedFeed(
            controllerProvider: homeFeedControllerProvider,
          ),
          // Global Trending
          PaginatedFeed(
            controllerProvider: globalFeedControllerProvider,
          ),
        ],
      ),
    );
  }
}
