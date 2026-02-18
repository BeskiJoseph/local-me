import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/repositories/social_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SocialRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SocialRepository(firestore: firestore);
  });

  group('SocialRepository', () {
    test('toggleLikePost adds like and increments count', () async {
      await firestore.collection('posts').doc('post1').set({
        'authorId': 'u2',
        'likeCount': 0,
      });

      await repo.toggleLikePost('post1', 'user1');

      final likeDoc = await firestore.collection('likes').doc('post1_user1').get();
      expect(likeDoc.exists, isTrue);

      final postDoc = await firestore.collection('posts').doc('post1').get();
      expect(postDoc.data()!['likeCount'], 1);
    });

    test('toggleLikePost removes like and decrements count', () async {
      // Setup existing like
      await firestore.collection('posts').doc('post1').set({
        'authorId': 'u2',
        'likeCount': 1,
      });
      await firestore.collection('likes').doc('post1_user1').set({
        'userId': 'user1',
        'postId': 'post1',
      });

      await repo.toggleLikePost('post1', 'user1');

      final likeDoc = await firestore.collection('likes').doc('post1_user1').get();
      expect(likeDoc.exists, isFalse);

      final postDoc = await firestore.collection('posts').doc('post1').get();
      expect(postDoc.data()!['likeCount'], 0);
    });

    test('followUser creates follow and updates counts', () async {
      await firestore.collection('users').doc('user1').set({'followingCount': 0});
      await firestore.collection('users').doc('user2').set({'subscribers': 0});

      await repo.followUser('user1', 'user2');

      final followDoc = await firestore.collection('follows').doc('user1_user2').get();
      expect(followDoc.exists, isTrue);

      final u1 = await firestore.collection('users').doc('user1').get();
      expect(u1.data()!['followingCount'], 1);

      final u2 = await firestore.collection('users').doc('user2').get();
      expect(u2.data()!['subscribers'], 1);
    });

    test('isPostLikedStream emits correct value', () async {
        final stream = repo.isPostLikedStream('post1', 'user1');
        
        expect(stream, emitsInOrder([false, true]));

        await Future.delayed(Duration.zero);
        await firestore.collection('likes').doc('post1_user1').set({'exists': true});
    });
  });
}
