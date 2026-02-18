import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/post.dart';

/// Repository for handling Post and Event data operations.
/// Accepts [FirebaseFirestore] and [FirebaseAuth] for dependency injection.
class PostRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  PostRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  List<Post> _postsFromQuerySnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final posts = snapshot.docs
        .map((doc) => Post.fromMap(doc.id, doc.data()))
        .toList();
    posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return posts;
  }

  Future<String> createPost({
    required String authorId,
    required String authorName,
    required String title,
    required String body,
    String scope = 'local',
    double? latitude,
    double? longitude,
    String? city,
    String? country,
    String category = 'General',
    String? mediaUrl,
    String mediaType = 'image',
    String? thumbnailUrl,
    String? authorProfileImage,
  }) async {
    final ref = _db.collection('posts').doc();
    await ref.set({
      'authorId': authorId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'title': title,
      'body': body,
      'scope': scope,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'commentCount': 0,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'country': country,
      'category': category,
      'thumbnailUrl': thumbnailUrl,
    });
    return ref.id;
  }

  Future<void> deletePost(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw "Not logged in";
    await _db.collection('posts').doc(postId).delete();
  }

  Stream<List<Post>> postsByScope(String scope) {
    final query = _db.collection('posts').where('scope', isEqualTo: scope);
    if (kIsWeb) {
      return Stream.periodic(const Duration(seconds: 2))
          .asyncMap((_) => query.get())
          .map(_postsFromQuerySnapshot)
          .asBroadcastStream();
    }
    return query.snapshots().map(_postsFromQuerySnapshot);
  }

  Future<List<Post>> getPostsPaginated({
    required String feedType,
    String? userCity,
    String? userCountry,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection('posts')
        .orderBy('createdAt', descending: true);

    if (feedType == 'local' && userCity != null) {
      query = query.where('city', isEqualTo: userCity);
    } else if (feedType == 'national' && userCountry != null) {
      query = query.where('country', isEqualTo: userCountry);
    }

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    query = query.limit(limit);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
  }

  Stream<List<Post>> postsForFeed({
    required String feedType,
    String? userCity,
    String? userCountry,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('posts');

    if (feedType == 'local' && userCity != null) {
      query = query.where('city', isEqualTo: userCity);
    } else if (feedType == 'national' && userCountry != null) {
      query = query.where('country', isEqualTo: userCountry);
    }
    
    query = query.orderBy('createdAt', descending: true).limit(20);

    if (kIsWeb) {
      return Stream.periodic(const Duration(seconds: 2))
          .asyncMap((_) => query.get())
          .map(_postsFromQuerySnapshot)
          .asBroadcastStream();
    }

    return query.snapshots().map(_postsFromQuerySnapshot);
  }

  Stream<List<Post>> postsByAuthor(String authorId) {
    final query =
        _db.collection('posts').where('authorId', isEqualTo: authorId);

    if (kIsWeb) {
      return Stream.periodic(const Duration(seconds: 2))
          .asyncMap((_) => query.get())
          .map(_postsFromQuerySnapshot)
          .asBroadcastStream();
    }

    return query.snapshots().map(_postsFromQuerySnapshot);
  }

  Stream<QuerySnapshot> getPostsStream() {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  // Event related methods
  Stream<int> eventAttendeesCountStream(String eventId) {
    return _db
        .collection('posts')
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.data()?['attendeeCount'] as int? ?? 0);
  }

  Stream<bool> isAttendingEventStream(String eventId, String userId) {
    final attendanceId = '${eventId}_$userId';
    return _db
        .collection('event_attendance')
        .doc(attendanceId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<void> toggleEventAttendance(String eventId, String userId) async {
    final postRef = _db.collection('posts').doc(eventId);
    final attendanceId = '${eventId}_$userId';
    final attendanceRef = _db.collection('event_attendance').doc(attendanceId);

    await _db.runTransaction((transaction) async {
      final attendanceDoc = await transaction.get(attendanceRef);

      if (attendanceDoc.exists) {
        transaction.delete(attendanceRef);
        transaction.update(postRef, {'attendeeCount': FieldValue.increment(-1)});
      } else {
        transaction.set(attendanceRef, {
          'eventId': eventId,
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {'attendeeCount': FieldValue.increment(1)});
      }
    }).catchError((e) {
      if (kDebugMode) print("Attendance Toggle Error: $e");
      throw "Action failed. Check your connection.";
    });
  }

  Future<void> createEvent({
    required String authorId,
    required String authorName,
    String? authorProfileImage,
    required String title,
    required String description,
    required String eventType,
    required DateTime eventDate,
    required String location,
    required double latitude,
    required double longitude,
    required String city,
    required String country,
    String? mediaUrl,
    bool isFree = true,
  }) async {
    await _db.collection('posts').add({
      'authorId': authorId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'title': title,
      'body': description,
      'eventType': eventType,
      'eventDate': Timestamp.fromDate(eventDate),
      'eventLocation': location,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'country': country,
      'mediaUrl': mediaUrl,
      'mediaType': 'image',
      'isFree': isFree,
      'isEvent': true,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'commentCount': 0,
      'attendeeCount': 0,
      'category': 'Events',
      'scope': 'global',
    });
  }
}
