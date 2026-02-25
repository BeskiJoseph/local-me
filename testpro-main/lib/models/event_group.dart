class EventGroup {
  final String id;
  final String eventId;
  final String creatorId;
  final String groupStatus; // 'active' or 'archived'
  final DateTime? createdAt;

  EventGroup({
    required this.id,
    required this.eventId,
    required this.creatorId,
    required this.groupStatus,
    this.createdAt,
  });

  factory EventGroup.fromJson(Map<String, dynamic> json, String documentId) {
    return EventGroup(
      id: documentId,
      eventId: json['eventId'] as String,
      creatorId: json['creatorId'] as String,
      groupStatus: json['groupStatus'] as String? ?? 'active',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventId': eventId,
      'creatorId': creatorId,
      'groupStatus': groupStatus,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}
