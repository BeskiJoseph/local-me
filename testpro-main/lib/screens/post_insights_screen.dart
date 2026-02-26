import 'package:flutter/material.dart';
import '../models/post.dart';
import '../config/app_theme.dart';
import '../services/backend_service.dart';
import '../shared/widgets/user_avatar.dart';

class PostInsightsScreen extends StatefulWidget {
  final Post post;

  const PostInsightsScreen({super.key, required this.post});

  @override
  State<PostInsightsScreen> createState() => _PostInsightsScreenState();
}

class _PostInsightsScreenState extends State<PostInsightsScreen> {
  bool _isLoading = true;
  int _viewCount = 0;
  List<Map<String, dynamic>> _viewers = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isLoading = true);
    try {
      final response = await BackendService.getPostInsights(widget.post.id);
      if (response.success && response.data != null) {
        setState(() {
          _viewCount = response.data!['viewCount'] ?? 0;
          _viewers = List<Map<String, dynamic>>.from(response.data!['viewers'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF1C1C1E), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Post Insights',
          style: TextStyle(
            color: Color(0xFF1C1C1E),
            fontWeight: FontWeight.w700,
            fontSize: 17,
            fontFamily: AppTheme.fontFamily,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  
                  // Stats Cards
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.visibility_rounded,
                            label: 'Views',
                            value: _viewCount.toString(),
                            color: const Color(0xFF2E7D6A),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.favorite_rounded,
                            label: 'Likes',
                            value: widget.post.likeCount.toString(),
                            color: const Color(0xFFE53935),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Comments',
                            value: widget.post.commentCount.toString(),
                            color: const Color(0xFF2196F3),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Viewers Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Who viewed your post',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                            fontFamily: AppTheme.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_viewers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(
                              child: Text(
                                'No views yet',
                                style: TextStyle(
                                  color: Color(0xFF8A8A8A),
                                  fontSize: 14,
                                  fontFamily: AppTheme.fontFamily,
                                ),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _viewers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final viewer = _viewers[index];
                              return _ViewerTile(viewer: viewer);
                            },
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
              fontFamily: AppTheme.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A8A8A),
              fontFamily: AppTheme.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  final Map<String, dynamic> viewer;

  const _ViewerTile({required this.viewer});

  @override
  Widget build(BuildContext context) {
    final String name = viewer['userName'] ?? 'User';
    final String? avatarUrl = viewer['userAvatar'];
    final String? location = viewer['location'];
    final String viewedAt = _formatTime(viewer['viewedAt']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          UserAvatar(
            imageUrl: avatarUrl,
            name: name,
            radius: 22,
            backgroundColor: AppTheme.primaryLight,
            initialsColor: AppTheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
                const SizedBox(height: 2),
                if (location != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 14, color: Color(0xFF8A8A8A)),
                      const SizedBox(width: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8A8A8A),
                          fontFamily: AppTheme.fontFamily,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Text(
            viewedAt,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A8A8A),
              fontFamily: AppTheme.fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      DateTime dateTime;
      if (timestamp is String) {
        dateTime = DateTime.parse(timestamp);
      } else {
        return '';
      }
      
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${(difference.inDays / 7).floor()}w ago';
      }
    } catch (e) {
      return '';
    }
  }
}
