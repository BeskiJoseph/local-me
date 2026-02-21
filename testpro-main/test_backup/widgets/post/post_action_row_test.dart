import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/widgets/post/post_action_row.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Not needed if we don't use Timestamp

void main() {
  group('PostActionRow Widget Test', () {
    final mockPost = Post(
      id: 'post123',
      title: 'Test Post',
      body: 'Content',
      authorId: 'u1',
      authorName: 'User 1',
      createdAt: DateTime.now(),
      likeCount: 10,
      commentCount: 5,
      isEvent: false,
      scope: 'public',
      mediaUrl: null,
      mediaType: 'text',
      attendeeCount: 0,
    );

    testWidgets('renders like count and comment count correctly', (WidgetTester tester) async {
      final streamController = StreamController<bool>();
      streamController.add(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostActionRow(
              post: mockPost,
              currentUserId: 'testUser',
              isLikedStream: streamController.stream,
              onLikeToggle: (id) async { return true; },
            ),
          ),
        ),
      );

      expect(find.text('Useful'), findsOneWidget); 
      expect(find.text('10'), findsOneWidget); 
      expect(find.text('5'), findsOneWidget); 
      expect(find.text('Replies'), findsOneWidget);

      await streamController.close();
    });

    testWidgets('optimistic update on like tap', (WidgetTester tester) async {
      final streamController = StreamController<bool>();
      streamController.add(false);

      bool toggleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostActionRow(
              post: mockPost,
              currentUserId: 'testUser',
              isLikedStream: streamController.stream,
              onLikeToggle: (id) async {
                toggleCalled = true;
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Useful'));
      await tester.pump(); 

      expect(find.text('11'), findsOneWidget); 
      
      await tester.pump(const Duration(milliseconds: 200)); 
      
      expect(toggleCalled, isTrue);

      await streamController.close();
    });
  });
}
