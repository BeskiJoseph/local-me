import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/post.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Avoid if possible for unit tests

void main() {
  group('Post Model', () {
    test('Post.fromMap correctly parses basic data', () {
      final data = {
        'title': 'Test Post',
        'body': 'This is content',
        'authorId': 'u123',
        'authorName': 'Test User',
        'createdAt': DateTime.now(), // Use DateTime
        'mediaUrl': 'http://image.com/1.jpg',
        'mediaType': 'image',
        'isEvent': false,
        'likeCount': 10,
        'commentCount': 5,
        'scope': 'public',
        'attendeeCount': 0,
      };

      final post = Post.fromMap('post123', data);

      expect(post.id, 'post123');
      expect(post.title, 'Test Post');
      expect(post.body, 'This is content');
      expect(post.authorId, 'u123');
      expect(post.likeCount, 10);
      expect(post.isEvent, false);
    });

    test('Post.fromMap correctly handles null values (defaults)', () {
      final data = {
        'title': 'Test Post',
        'body': 'Content',
        'authorId': 'u123',
        'authorName': 'Test User',
        'createdAt': DateTime.now(),
        'scope': 'public',
        'attendeeCount': 0,
        // missing mediaUrl, mediaType, etc.
      };

      final post = Post.fromMap('post123', data);

      expect(post.likeCount, 0); 
      expect(post.commentCount, 0); 
      expect(post.mediaType, 'image'); // Default
    });

    test('Post.toMap correctly serializes data', () {
      final now = DateTime.now();
      final post = Post(
        id: 'post123',
        title: 'Test Post',
        body: 'Content',
        authorId: 'u123',
        authorName: 'Test User',
        createdAt: now,
        mediaUrl: 'http://image.com/1.jpg',
        mediaType: 'image',
        isEvent: false,
        likeCount: 10,
        commentCount: 5,
        scope: 'public',
        attendeeCount: 0,
      );

      final map = post.toMap();

      expect(map['title'], 'Test Post');
      expect(map['authorId'], 'u123');
      expect(map['createdAt'], now);
    });
  });
}
