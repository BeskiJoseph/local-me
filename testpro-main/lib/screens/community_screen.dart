import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/core/events/feed_events.dart';
import '../models/post.dart';
import 'group_chat_screen.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../utils/proxy_helper.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _activeCategoryIndex = 1; // 1: Events
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Holds the user's joined event IDs
  List<String>? _myEventIds;
  bool _isLoading = true;
  StreamSubscription<FeedEvent>? _eventSubscription;
  late Stream<List<Post>> _eventPostsStream;

  @override
  void initState() {
    super.initState();
    _eventPostsStream = PostService.postsByScope('Events');
    _loadMyEvents();
    _eventSubscription = FeedEventBus.events.listen((event) {
      if (!mounted) return;
      if (event.type == FeedEventType.postCreated ||
          event.type == FeedEventType.eventMembershipChanged) {
        setState(() {
          _eventPostsStream = PostService.postsByScope('Events');
        });
        _loadMyEvents();
      }
    });
  }

  Future<void> _loadMyEvents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await BackendService.getMyEventIds();
      if (response.success && response.data != null) {
        if (mounted) {
          setState(() {
            _myEventIds = response.data!;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _myEventIds = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myEventIds = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMyEvents,
          color: AppTheme.primary,
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
                        'My Events',
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
      ),
    );
  }

  Widget _buildEventsList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final myEventIds = _myEventIds ?? [];

    if (myEventIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_available, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'No events joined yet.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Join events from the Home feed to see them here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<List<Post>>(
      stream: _eventPostsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final allEventPosts = snapshot.data ?? [];

        // Filter: Only show events that the user has joined AND are not archived
        final filteredPosts = allEventPosts.where((post) {
          if (!myEventIds.contains(post.id)) return false;
          if (post.computedStatus == 'archived') return false;
          final title = post.title.toLowerCase();
          final body = post.body.toLowerCase();
          return title.contains(_searchQuery) || body.contains(_searchQuery);
        }).toList();

        if (filteredPosts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                _searchQuery.isNotEmpty
                    ? 'No matching events found.'
                    : 'No active events right now.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filteredPosts.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final post = filteredPosts[index];
            return _ChatGroupTile(
              post: post,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupChatScreen(event: post),
                  ),
                );
              },
            );
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
          color: isActive ? AppTheme.primary.withValues(alpha: 0.1) : const Color(0xFFF0F1F3),
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

// ─────────────────────────────────────────────────────────────
// Chat Group Tile — messaging-app style for joined events
// ─────────────────────────────────────────────────────────────
class _ChatGroupTile extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const _ChatGroupTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateStr = post.eventStartDate != null
        ? DateFormat('MMM dd, yyyy • h:mm a').format(post.eventStartDate!)
        : '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // ── Event Logo (cover image) ──
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _EventLogo(post: post),
                ),
              ),
              const SizedBox(width: 14),

              // ── Title & Date ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppTheme.fontFamily,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              fontFamily: AppTheme.fontFamily,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Attendee badge + chat icon ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people, size: 13, color: AppTheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          '${post.attendeeCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventLogo extends StatelessWidget {
  final Post post;
  const _EventLogo({required this.post});

  @override
  Widget build(BuildContext context) {
    final rawUrl = post.thumbnailUrl ?? post.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      return Container(
        color: AppTheme.primary.withValues(alpha: 0.1),
        child: const Icon(Icons.groups_rounded, color: AppTheme.primary, size: 28),
      );
    }

    return CachedNetworkImage(
      imageUrl: ProxyHelper.getUrl(rawUrl),
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey.shade100,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppTheme.primary.withValues(alpha: 0.1),
        child: const Icon(Icons.groups_rounded, color: AppTheme.primary, size: 28),
      ),
    );
  }
}
