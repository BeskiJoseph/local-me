import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../services/auth_service.dart';
import '../../services/post_service.dart';
import '../../services/backend_service.dart';

class EventAttendanceSection extends StatefulWidget {
  final Post post;
  final String? currentUserId;
  final Stream<int>? attendeesCountStream;
  final Stream<bool>? isAttendingStream;
  final Future<void> Function(String)? onToggleJoin;

  const EventAttendanceSection({
    super.key,
    required this.post,
    this.currentUserId,
    this.attendeesCountStream,
    this.isAttendingStream,
    this.onToggleJoin,
  });

  @override
  State<EventAttendanceSection> createState() => _EventAttendanceSectionState();
}

class _EventAttendanceSectionState extends State<EventAttendanceSection> {
  bool? _optimisticAttending;
  int? _optimisticAttendeeCount;

  @override
  Widget build(BuildContext context) {
    final userId = widget.currentUserId ?? AuthService.currentUser?.uid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Attendees Count
          StreamBuilder<int>(
            stream: widget.attendeesCountStream ?? PostService.eventAttendeesCountStream(widget.post.id),
            builder: (context, snapshot) {
              final streamCount = snapshot.data ?? widget.post.attendeeCount;
              final displayCount = _optimisticAttendeeCount ?? streamCount;

              return Row(
                children: [
                  Icon(
                    Icons.people,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$displayCount ${displayCount == 1 ? 'person' : 'people'} going',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),

          const Spacer(),

          // Join/Leave Button
          if (userId != null)
            StreamBuilder<bool>(
              stream: widget.isAttendingStream ?? PostService.isAttendingEventStream(
                widget.post.id,
                userId,
              ),
              builder: (context, snapshot) {
                final streamAttending = snapshot.data ?? false;
                final isAttending = _optimisticAttending ?? streamAttending;

                return Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: isAttending
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF00B87C), Color(0xFF00D68F)],
                          ),
                    color: isAttending ? Colors.grey.shade200 : null,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isAttending
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFF00B87C).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      final bool currentAttending = _optimisticAttending ?? streamAttending;
                      final bool newTarget = !currentAttending;
                      
                      int streamCount = widget.post.attendeeCount; // Fallback
                      
                      setState(() {
                        _optimisticAttending = newTarget;
                        _optimisticAttendeeCount = newTarget 
                            ? (_optimisticAttendeeCount ?? streamCount) + 1 
                            : (_optimisticAttendeeCount ?? streamCount) - 1;
                        if (_optimisticAttendeeCount! < 0) _optimisticAttendeeCount = 0;
                      });

                      try {
                        if (widget.onToggleJoin != null) {
                          await widget.onToggleJoin!(widget.post.id);
                        } else {
                          final response = await BackendService.toggleEventJoin(widget.post.id);
                          if (!response.success) throw response.error ?? "Toggle failed";
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _optimisticAttending = null;
                            _optimisticAttendeeCount = null;
                          });
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isAttending ? Icons.check_circle : Icons.add_circle_outline,
                          size: 18,
                          color: isAttending ? Colors.grey.shade700 : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isAttending ? 'Going' : 'Join',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isAttending ? Colors.grey.shade700 : Colors.white,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
