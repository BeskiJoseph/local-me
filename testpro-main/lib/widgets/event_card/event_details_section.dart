import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/post.dart';

class EventDetailsSection extends StatelessWidget {
  final Post post;

  const EventDetailsSection({super.key, required this.post});

  String _formatEventDate(DateTime date) {
    return DateFormat('EEE, MMM d').format(date);
  }

  String _formatEventTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Title
          Text(
            post.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'Inter',
              color: Color(0xFF1C1C1E),
            ),
          ),

          const SizedBox(height: 12),

          // Event Date & Time
          if (post.eventStartDate != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B6B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Color(0xFFFF6B6B),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatEventDate(post.eventStartDate!),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatEventTime(post.eventStartDate!),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),

          const SizedBox(height: 12),

          // Location
          if (post.eventLocation != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B87C).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    size: 16,
                    color: Color(0xFF00B87C),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    post.eventLocation!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1C1C1E),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

        ],
      ),
    );
  }
}
