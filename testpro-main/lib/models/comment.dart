class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorProfileImage;
  final String text;
  final DateTime createdAt;
  final int likeCount;
  final int replyCount;
  final bool isLiked;
  final String? parentId;

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    this.authorProfileImage,
    required this.text,
    required this.createdAt,
    this.likeCount = 0,
    this.replyCount = 0,
    this.isLiked = false,
    this.parentId,
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
      likeCount: json['likeCount'] as int? ?? 0,
      replyCount: json['replyCount'] as int? ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      parentId: json['parentId'] as String?,
    );
  }

  factory Comment.fromMap(Map<String, dynamic> map) => Comment.fromJson(map);

  Comment copyWith({
    int? likeCount,
    int? replyCount,
    bool? isLiked,
  }) {
    return Comment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorProfileImage: authorProfileImage,
      text: text,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      replyCount: replyCount ?? this.replyCount,
      isLiked: isLiked ?? this.isLiked,
      parentId: parentId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'postId': postId,
      'authorId': authorId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'likeCount': likeCount,
      'replyCount': replyCount,
      'isLiked': isLiked,
      'parentId': parentId,
    };
  }
}
