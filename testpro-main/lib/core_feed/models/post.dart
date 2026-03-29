class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorProfileImage;
  final String? title;
  final String? body;
  final String? mediaUrl;
  final String mediaType; // 'image' or 'video'
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;
  final bool isLiked;
  final bool isFollowing;

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorProfileImage,
    this.title,
    this.body,
    this.mediaUrl,
    required this.mediaType,
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.isLiked = false,
    this.isFollowing = false,
  });

  Post copyWith({
    bool? isLiked,
    int? likeCount,
    bool? isFollowing,
    int? commentCount,
    int? viewCount,
  }) {
    return Post(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorProfileImage: authorProfileImage,
      title: title,
      body: body,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      createdAt: createdAt,
      latitude: latitude,
      longitude: longitude,
      isLiked: isLiked ?? this.isLiked,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
