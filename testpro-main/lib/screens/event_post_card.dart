import 'package:flutter/material.dart';
import '../models/post.dart';
import '../widgets/event_card/event_card_image.dart';
import '../widgets/event_card/event_details_section.dart';
import '../widgets/event_card/event_attendance_section.dart';
import '../widgets/event_card/event_card_footer.dart';

class EventPostCard extends StatefulWidget {
  final Post post;

  const EventPostCard({super.key, required this.post});

  @override
  State<EventPostCard> createState() => _EventPostCardState();
}

class _EventPostCardState extends State<EventPostCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A000000),
            offset: const Offset(0, 6),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Image
          EventCardImage(post: widget.post),
          
          // Event Details
          EventDetailsSection(post: widget.post),
          
          // Attendees & Join Button
          EventAttendanceSection(post: widget.post),

          // Footer (Organizer & Interactions)
          EventCardFooter(post: widget.post),
        ],
      ),
    );
  }
}