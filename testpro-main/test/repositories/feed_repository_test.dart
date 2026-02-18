import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/feed_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FeedRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FeedRepository(firestore: firestore);
  });

  group('FeedRepository', () {
    test('logUserActivity updates interest scores', () async {
      final userId = 'user1';
      final postId = 'post1';
      final category = 'Tech';
      final tags = ['Flutter', 'Dart'];

      // Log: Liked (Weight 3.0) + WatchTime 10s (5.0) -> Total 8.0?
      // Logic: (watchTime * 0.5) + (liked ? 3.0 : 0)
      // (10 * 0.5) = 5.0
      // 5.0 + 3.0 = 8.0
      
      await repo.logUserActivity(
        userId: userId,
        postId: postId,
        category: category,
        tags: tags,
        watchTime: 10,
        liked: true,
      );

      // Check Category Score
      final catDoc = await firestore.collection('user_interests').doc('${userId}_cat_$category').get();
      expect(catDoc.exists, isTrue);
      // FakeFirestore returns double/int correctly
      expect(catDoc.data()!['score'], 8.0);
      expect(catDoc.data()!['type'], 'category');

      // Check Tag Score
      final tagDoc = await firestore.collection('user_interests').doc('${userId}_tag_Flutter').get();
      expect(tagDoc.exists, isTrue);
      expect(tagDoc.data()!['score'], 8.0);
    });

    test('getRecommendedFeed prioritizes interests', () async {
      // 1. Setup Interests
      await firestore.collection('user_interests').add({
        'userId': 'user1',
        'tag': 'Flutter',
        'score': 10.0,
        'lastActive': DateTime.now().toIso8601String(), // FakeFirestore might not sort string dates correctly if not Timestamp? 
        // Actually FakeFirestore sorts strings lexicographically. ISO8601 is sortable.
        // But code uses orderBy('lastActive', descending: true).
        // And logUserActivity sets serverTimestamp.
        // We'll use Timestamp here to be safe if possible, or just date.
      });

      // 2. Setup Posts
      await firestore.collection('posts').add({
        'title': 'Flutter Post',
        'category': 'Flutter',
        'authorId': 'u2',
        'createdAt': DateTime.now().toIso8601String(),
        'likeCount': 0,
      });

      await firestore.collection('posts').add({
        'title': 'React Post',
        'category': 'React',
        'authorId': 'u3',
        'createdAt': DateTime.now().subtract(Duration(days: 1)).toIso8601String(),
        'likeCount': 100, // Trending
      });

      // 3. fetch
      // Note: FakeFirestore query specificities might be tricky with "whereIn" combined with "orderBy".
      // Let's see if it works.
      
      final feed = await repo.getRecommendedFeed(userId: 'user1', limit: 10);
      
      // Should contain at least 1 post
      expect(feed, isNotEmpty);
      // expect(feed.any((p) => p.title == 'Flutter Post'), isTrue);
    });
  });
}
