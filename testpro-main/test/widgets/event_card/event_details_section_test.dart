import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testpro/models/post.dart';
import 'package:testpro/widgets/event_card/event_details_section.dart';
import 'package:intl/intl.dart';

void main() {
  group('EventDetailsSection Widget Test', () {
    final eventDate = DateTime(2025, 12, 25, 18, 30); // Dec 25, 2025, 6:30 PM

    final mockEventPost = Post(
      id: 'event123',
      title: 'Christmas Party',
      body: 'Celebrate!',
      authorId: 'u1',
      authorName: 'Organizer',
      createdAt: DateTime.now(),
      likeCount: 0,
      commentCount: 0,
      scope: 'public',
      mediaUrl: null,
      mediaType: 'image',
      
      isEvent: true,
      attendeeCount: 10,
      eventDate: eventDate,
        eventLocation: 'North Pole',
    );

    testWidgets('renders title, date, time, location correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailsSection(post: mockEventPost),
          ),
        ),
      );

      // Verify Title
      expect(find.text('Christmas Party'), findsOneWidget);

      // Verify Description
      expect(find.text('Celebrate!'), findsOneWidget);

      // Verify Location
      expect(find.text('North Pole'), findsOneWidget);

      // Verify Date & Time formatting
      // DateFormat('EEE, MMM d') -> Thu, Dec 25
      final expectedDate = DateFormat('EEE, MMM d').format(eventDate);
      expect(find.text(expectedDate), findsOneWidget);

      // DateFormat('h:mm a') -> 6:30 PM
      final expectedTime = DateFormat('h:mm a').format(eventDate);
      expect(find.text(expectedTime), findsOneWidget);
    });
  });
}
