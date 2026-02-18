import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/signup_data.dart';
import 'package:testpro/repositories/user_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late UserRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    repo = UserRepository(firestore: firestore, auth: auth);
  });

  group('UserRepository', () {
    test('createUserProfile creates document', () async {
      final user = MockUser(
        uid: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
      );
      // SignupData has no named constructor, use cascade
      final data = SignupData()
        ..email = 'test@example.com'
        ..username = 'testuser'
        ..firstName = 'Test'
        ..lastName = 'User';

      await repo.createUserProfile(user: user, data: data);

      final doc = await firestore.collection('users').doc('user1').get();
      expect(doc.exists, isTrue);
      // Verify fields
      expect(doc.data()!['username'], 'testuser');
      expect(doc.data()!['email'], 'test@example.com');
      // Verify initialized counters
      expect(doc.data()!['contents'], 0);
      expect(doc.data()!['subscribers'], 0);
    });

    test('updateUserProfile updates fields', () async {
      // Setup initial state
      await firestore.collection('users').doc('user1').set({
        'username': 'oldName',
        'about': 'oldAbout',
        'contents': 5,
      });

      await repo.updateUserProfile(
        userId: 'user1',
        displayName: 'newName',
        about: 'newAbout',
      );

      final doc = await firestore.collection('users').doc('user1').get();
      expect(doc.data()!['username'], 'newName');
      expect(doc.data()!['about'], 'newAbout');
      // Unchanged fields remain
      expect(doc.data()!['contents'], 5);
    });

    test('incrementContentCount increments field', () async {
      // Setup
      await firestore.collection('users').doc('user1').set({
        'contents': 5,
      });

      await repo.incrementContentCount('user1');

      final doc = await firestore.collection('users').doc('user1').get();
      expect(doc.data()!['contents'], 6);
    });

    // Note: userProfileStream might fail if Stream logic relies on something not supported by fake_cloud_firestore fully
    // But fake supports basics.
    test('userProfileStream emits updates', () async {
      await firestore.collection('users').doc('user1').set({
        // Required fields for UserProfile.fromMap
        'id': 'user1',
        'username': 'User 1',
        'email': 'u1@test.com',
        'subscribers': 0,
        'followingCount': 0,
        'contents': 0,
      });

      // We expect the stream to emit the initial value, then the updated value
      // But Stream matchers can be tricky.
      // We'll collect first 2 events.
      
      final stream = repo.userProfileStream('user1');
      
      final events = <String?>[];
      final subscription = stream.listen((profile) {
        if (profile != null) events.add(profile.username);
      });

      // Wait for first emission
      await Future.delayed(Duration.zero);
      
      // Update
      await firestore.collection('users').doc('user1').update({'username': 'User 2'});
      
      // Wait for update
      await Future.delayed(Duration.zero);

      await subscription.cancel();
      
      expect(events, containsAllInOrder(['User 1', 'User 2']));
    });
  });
}
