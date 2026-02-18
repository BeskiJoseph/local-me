import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/post_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late PostRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    repo = PostRepository(firestore: firestore, auth: auth);
  });

  group('PostRepository', () {
    test('createPost adds a document to Firestore', () async {
      final postId = await repo.createPost(
        authorId: 'user1',
        authorName: 'Test User',
        title: 'New Post',
        body: 'Content',
        scope: 'local',
        category: 'General',
      );

      final doc = await firestore.collection('posts').doc(postId).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['title'], 'New Post');
      expect(doc.data()!['authorId'], 'user1');
      expect(doc.data()!['likeCount'], 0);
    });

    test('deletePost removes document if logged in', () async {
      // Setup: Create a post
      final ref = await firestore.collection('posts').add({
        'title': 'To Delete',
        'authorId': 'user1',
      });

      // Login
      await auth.signInWithCustomToken('user1');
      
      // Delete
      await repo.deletePost(ref.id);

      final doc = await firestore.collection('posts').doc(ref.id).get();
      expect(doc.exists, isFalse);
    });

    test('deletePost throws if not logged in', () async {
      await auth.signOut();
      
      expect(
        () => repo.deletePost('someId'),
        throwsA(isA<String>()), // "Not logged in"
      );
    });

    test('postsByScope returns filtered stream', () async {
      // Add posts
      await firestore.collection('posts').add({
        'title': 'Local Post',
        'scope': 'local',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await firestore.collection('posts').add({
        'title': 'Global Post',
        'scope': 'global',
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Listen to stream
      final localPosts = await repo.postsByScope('local').first;
      expect(localPosts.length, 1);
      expect(localPosts.first.title, 'Local Post');

      final globalPosts = await repo.postsByScope('global').first;
      expect(globalPosts.length, 1);
      expect(globalPosts.first.title, 'Global Post');
    });

    test('eventAttendeesCountStream updates in real-time', () async {
      final eventRef = await firestore.collection('posts').add({
        'isEvent': true,
        'attendeeCount': 5,
      });

      expect(
        repo.eventAttendeesCountStream(eventRef.id),
        emitsInOrder([5, 6]),
      );

      // Simulate update
      await eventRef.update({'attendeeCount': 6});
    });
  });
}
