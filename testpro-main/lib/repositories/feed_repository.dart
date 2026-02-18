import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';

/// Repository for handling Feed Recommendation and User Activity Logging.
/// Accepts [FirebaseFirestore] for dependency injection.
class FeedRepository {
  final FirebaseFirestore _db;

  FeedRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // Recommendation Weights (V3)
  static const double weightWatchTime = 0.5;
  static const double weightLike = 3.0;
  static const double weightComment = 4.0;
  static const double weightShare = 5.0;
  static const double weightSkipPenalty = -5.0;

  Future<void> logUserActivity({
    required String userId,
    required String postId,
    required String category,
    required List<String> tags,
    double watchTime = 0,
    bool liked = false,
    bool commented = false,
    bool shared = false,
    String? sessionId,
  }) async {
    try {
      final bool isEarlySkip = watchTime < 3 && !liked && !commented && !shared;
      
      // 1. Log Raw Activity for Analytics
      await _db.collection('user_activity').add({
        'userId': userId,
        'postId': postId,
        'sessionId': sessionId,
        'watchTime': watchTime,
        'liked': liked,
        'commented': commented,
        'shared': shared,
        'isEarlySkip': isEarlySkip,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Calculate Score Delta
      double scoreDelta = (watchTime * weightWatchTime) +
          (liked ? weightLike : 0) +
          (commented ? weightComment : 0) +
          (shared ? weightShare : 0);
      
      if (isEarlySkip) scoreDelta += weightSkipPenalty;

      if (scoreDelta == 0) return;

      final interestRef = _db.collection('user_interests');
      final baseId = '${userId}_';

      // Update Category Score
      await interestRef.doc('${baseId}cat_$category').set({
        'userId': userId,
        'tag': category,
        'type': 'category',
        'score': FieldValue.increment(scoreDelta),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Update Tag Scores (Top 5)
      for (var tag in tags.take(5)) {
        await interestRef.doc('${baseId}tag_$tag').set({
          'userId': userId,
          'tag': tag,
          'type': 'tag',
          'score': FieldValue.increment(scoreDelta),
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error logging activity: $e');
    }
  }

  Future<List<Post>> getRecommendedFeed({
    required String userId,
    String? sessionId,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) async {
    try {
      // mix: 60% Interests, 20% Trending, 10% New, 10% Discovery
      final int interestLimit = (limit * 0.6).floor();
      final int trendingLimit = (limit * 0.2).floor();
      final int newLimit = (limit * 0.1).floor();
      
      List<Post> results = [];
      final Set<String> seenPostIds = {};
      final Map<String, int> creatorCounts = {};

      void addWithFairness(List<dynamic> docs) {
        for (var doc in docs) {
          final post = Post.fromFirestore(doc); // Assumes doc matches standard Post parsing
          if (seenPostIds.contains(post.id)) continue;
          
          final count = creatorCounts[post.authorId] ?? 0;
          if (count < 2) {
            results.add(post);
            seenPostIds.add(post.id);
            creatorCounts[post.authorId] = count + 1;
          }
          if (results.length >= limit) break;
        }
      }

      // 1. Fetch Top Interests (Flat collection)
      final interestsSnapshot = await _db
          .collection('user_interests')
          .where('userId', isEqualTo: userId)
          .orderBy('lastActive', descending: true)
          .limit(10)
          .get();

      final topInterests = interestsSnapshot.docs
          .map((doc) => doc.data()) // Safe data access
          .where((data) => (data['score'] is num) && (data['score'] as num) > 0)
          .map((data) => data['tag'] as String)
          .toList();

      // 2. Query Personalized Posts
      if (topInterests.isNotEmpty) {
        // Firestore 'whereIn' supports up to 10 items
        final searchInterests = topInterests.take(10).toList();
        
        final personalSnapshot = await _db.collection('posts')
            .where('category', whereIn: searchInterests)
            .orderBy('createdAt', descending: true)
            .limit(interestLimit * 2) 
            .get();
        addWithFairness(personalSnapshot.docs);
      }

      // 3. Trending & New (Fallbacks)
      if (results.length < limit) {
        final trendingSnapshot = await _db.collection('posts')
            .orderBy('likeCount', descending: true)
            .limit(trendingLimit + 5)
            .get();
        addWithFairness(trendingSnapshot.docs);
      }

      if (results.length < limit) {
        final newSnapshot = await _db.collection('posts')
            .orderBy('createdAt', descending: true)
            .limit(newLimit + 5)
            .get();
        addWithFairness(newSnapshot.docs);
      }

      // 4. Fill remaining with Discovery
      if (results.length < limit) {
        final discoverySnapshot = await _db.collection('posts')
            .limit(limit)
            .get(); 
        addWithFairness(discoverySnapshot.docs);
      }

      results.shuffle();
      return results.take(limit).toList();
    } catch (e) {
      debugPrint('Recommendation Error: $e');
      final fallback = await _db.collection('posts').orderBy('createdAt', descending: true).limit(limit).get();
      return fallback.docs.map((d) => Post.fromFirestore(d)).toList();
    }
  }
}
