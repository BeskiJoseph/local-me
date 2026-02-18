import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/widgets/event_card/event_attendance_section.dart';

void main() {
  group('EventAttendanceSection Widget Test', () {
    final mockEventPost = Post(
      id: 'event123',
      title: 'Cool Event',
      body: 'Party!',
      authorId: 'u1',
      authorName: 'Organizer',
      createdAt: DateTime.now(),
        // Add required fields
      likeCount: 0,
      commentCount: 0,
      scope: 'public',
      mediaUrl: null,
      mediaType: 'image',
      
      isEvent: true,
      attendeeCount: 5,
      eventDate: DateTime.now().add(const Duration(days: 1)),
      eventLocation: 'Park',
    );

    testWidgets('renders attendee count and Join button for logged in user', (WidgetTester tester) async {
      final attendeesStreamController = StreamController<int>();
      attendeesStreamController.add(5);
      
      final attendingStreamController = StreamController<bool>();
      attendingStreamController.add(false); // Not attending

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventAttendanceSection(
              post: mockEventPost,
              currentUserId: 'user123',
              attendeesCountStream: attendeesStreamController.stream,
              isAttendingStream: attendingStreamController.stream,
              onToggleJoin: (id) async {},
            ),
          ),
        ),
      );

      // Verify attendees text
      expect(find.text('5 people going'), findsOneWidget);

      // Verify Join button
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Going'), findsNothing);

      await attendeesStreamController.close();
      await attendingStreamController.close();
    });

    testWidgets('optimistic update on Join button tap', (WidgetTester tester) async {
      final attendeesStreamController = StreamController<int>();
      attendeesStreamController.add(5);
      
      final attendingStreamController = StreamController<bool>();
      attendingStreamController.add(false);

      bool toggleCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventAttendanceSection(
              post: mockEventPost,
              currentUserId: 'user123',
              attendeesCountStream: attendeesStreamController.stream,
              isAttendingStream: attendingStreamController.stream,
              onToggleJoin: (id) async {
                toggleCalled = true;
              },
            ),
          ),
        ),
      );

      // Tap Join
      await tester.tap(find.text('Join'));
      await tester.pump(); // Rebuild with optimistic state

      // Verify Optimistic update
      // Count should increment: 5 -> 6
      expect(find.text('6 people going'), findsOneWidget);
      // Button text changes to 'Going'
      expect(find.text('Going'), findsOneWidget);
      
      // Wait for async call
      await tester.pump(const Duration(milliseconds: 100)); // Future/async logic
      
      expect(toggleCalled, isTrue);

      await attendeesStreamController.close();
      await attendingStreamController.close();
    });
  });
}
