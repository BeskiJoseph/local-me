import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../models/post.dart';
import '../shared/widgets/user_avatar.dart';
import '../screens/event_post_card.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _activeCategoryIndex = 1; // 1: Events
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Text(
                      'Community',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFamily: AppTheme.fontFamily,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  // ── Search Bar ──────────────────────────────────────────
                  _buildSearchBar(),

                  // ── Navigation Pills ────────────────────────────────────
                  _buildCategoryPills(),

                  const SizedBox(height: 16),

                   // ── My Events ───────────────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'All Events',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppTheme.fontFamily,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  _buildEventsList(),
                  
                  const SizedBox(height: 100), // Space for FAB/Bottom Nav
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEventsList() {
    return StreamBuilder<List<Post>>(
      stream: PostService.postsByScope('Events'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final posts = snapshot.data ?? [];
        final filteredPosts = posts.where((post) {
          final title = post.title.toLowerCase();
          final body = post.body.toLowerCase();
          return title.contains(_searchQuery) || body.contains(_searchQuery);
        }).toList();

        if (filteredPosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Text(
                'No events found.',
                style: TextStyle(color: Color(0xFF8A8A8A)),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16),
          itemCount: filteredPosts.length,
          itemBuilder: (context, index) {
            return EventPostCard(post: filteredPosts[index]);
          },
        );
      }
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search events...',
                  hintStyle: TextStyle(
                    color: const Color(0xFF8A8A8A),
                    fontSize: 15,
                    fontFamily: AppTheme.fontFamily,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8A8A8A), size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.tune_rounded, color: Color(0xFF1A1A1A), size: 26),
        ],
      ),
    );
  }

  Widget _buildCategoryPills() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _CategoryPill(
            icon: Icons.calendar_today_outlined,
            label: 'Events',
            isActive: _activeCategoryIndex == 1,
            onTap: () => setState(() => _activeCategoryIndex = 1),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primary.withOpacity(0.1) : const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isActive ? AppTheme.primary : const Color(0xFF8A8A8A)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.fontFamily,
                color: isActive ? AppTheme.primary : const Color(0xFF8A8A8A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


