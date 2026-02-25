class EventGroupMember {
  final String id;
  final String eventId;
  final String userId;
  final String role; // 'admin' or 'member'
  final DateTime? joinedAt;

  EventGroupMember({
    required this.id,
    required this.eventId,
    required this.userId,
    required this.role,
    this.joinedAt,
  });

  factory EventGroupMember.fromJson(Map<String, dynamic> json, String documentId) {
    return EventGroupMember(
      id: documentId,
      eventId: json['eventId'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String? ?? 'member',
      joinedAt: json['joinedAt'] != null ? DateTime.tryParse(json['joinedAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'userId': userId,
      'role': role,
      if (joinedAt != null) 'joinedAt': joinedAt!.toIso8601String(),
    };
  }
}
