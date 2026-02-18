import 'package:flutter/material.dart';
import '../../services/firestore_service.dart';
import '../../models/post.dart';
import '../nextdoor_post_card.dart';
import '../../screens/event_post_card.dart';

class HomeFeedList extends StatelessWidget {
  final String feedType;
  final String? userCity;
  final String? userCountry;
  final bool isLoadingLocation;
  final String? locationError;
  final VoidCallback onRetryLocation;
  final String searchQuery;
  final ScrollController scrollController;

  const HomeFeedList({
    super.key,
    required this.feedType,
    required this.userCity,
    required this.userCountry,
    required this.isLoadingLocation,
    required this.locationError,
    required this.onRetryLocation,
    required this.searchQuery,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingLocation) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00B87C)));
    }

    if (locationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                locationError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetryLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B87C),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (feedType == 'local' && userCity == null) {
      return const Center(child: Text('Waiting for location...'));
    }
    if ((feedType == 'national' || feedType == 'global') && userCountry == null) {
      return const Center(child: Text('Waiting for location...'));
    }

    return StreamBuilder<List<Post>>(
      stream: FirestoreService.postsForFeed(
        feedType: feedType,
        userCity: userCity,
        userCountry: userCountry,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00B87C)));
        }

        if (snapshot.hasError) {
          return Center(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
             ),
          );
        }

        final posts = snapshot.data ?? [];
        
        final filteredPosts = searchQuery.isEmpty
            ? posts
            : posts.where((post) {
                final searchLower = searchQuery.toLowerCase();
                return post.title.toLowerCase().contains(searchLower) ||
                       post.body.toLowerCase().contains(searchLower) ||
                       post.authorName.toLowerCase().contains(searchLower) ||
                       post.category.toLowerCase().contains(searchLower);
              }).toList();

        if (filteredPosts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.forum_outlined, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isEmpty ? 'No posts yet in this area' : 'No posts found',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                if (searchQuery.isEmpty)
                  Text(
                    '$userCity, $userCountry',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.only(top: 0, bottom: 100),
          itemCount: filteredPosts.length,
          separatorBuilder: (context, index) => Container(
            height: 8,
            color: const Color(0xFFF0F0F0),
          ),
          itemBuilder: (context, index) {
            final post = filteredPosts[index];
            if (post.isEvent) {
              return EventPostCard(post: post);
            }
            return NextdoorStylePostCard(
              post: post,
              currentCity: userCity,
            );
          },
        );
      },
    );
  }
}
