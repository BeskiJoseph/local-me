class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? senderProfileImage;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderProfileImage,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> data = json['data'] ?? json;
    final String actualId = json['id'] as String? ?? '';
    
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      if (date is DateTime) return date;
      return DateTime.tryParse(date.toString()) ?? DateTime.now();
    }

    return ChatMessage(
      id: actualId,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderProfileImage: data['senderProfileImage'],
      text: data['text'] ?? '',
      timestamp: parseDate(data['timestamp']),
    );
  }

  // Backward compatibility
  factory ChatMessage.fromMap(Map<String, dynamic> data, [String? id]) {
    return ChatMessage.fromJson({...data, if (id != null) 'id': id});
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderProfileImage': senderProfileImage,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
