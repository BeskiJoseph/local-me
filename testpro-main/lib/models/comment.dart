class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorProfileImage;
  final String text;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorProfileImage,
    required this.text,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      if (date is DateTime) return date;
      return DateTime.tryParse(date.toString()) ?? DateTime.now();
    }

    return Comment(
      id: json['id'] as String? ?? '',
      postId: json['postId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'User',
      authorProfileImage: json['authorProfileImage'] as String?,
      text: json['text'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
    );
  }

  factory Comment.fromMap(Map<String, dynamic> map) => Comment.fromJson(map);


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'authorId': authorId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
