import 'package:cloud_firestore/cloud_firestore.dart';

class SearchService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Search users by username
  static Stream<QuerySnapshot> searchUsers(String query) {
    if (query.isEmpty) {
      return const Stream.empty();
    }

    // Search by username (case-insensitive prefix match)
    // Basic implementation - for better results use Algolia/Typesense
    return _db
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: query)
        .where('username', isLessThanOrEqualTo: '$query\uf8ff')
        .limit(20)
        .snapshots();
  }

  // Search posts by title
  static Stream<QuerySnapshot> searchPosts(String query) {
    if (query.isEmpty) {
      return const Stream.empty();
    }

    return _db
        .collection('posts')
        .where('title', isGreaterThanOrEqualTo: query)
        .where('title', isLessThanOrEqualTo: '$query\uf8ff')
        .orderBy('title')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }
}
