class Post {
  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String body;
  final String? authorProfileImage;
  final String scope;
  final String? mediaUrl;
  final String mediaType;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? country;
  final String category;
  final String? thumbnailUrl;
  
  // Event fields
  final bool isEvent;
  final String? eventType;
  final DateTime? eventDate;
  final String? eventLocation;
  final bool? isFree;
  final int attendeeCount;

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.scope,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.likeCount,
    required this.commentCount,
    this.latitude,
    this.longitude,
    this.city,
    this.country,
    this.category = 'General',
    this.thumbnailUrl,
    this.authorProfileImage,
    required this.isEvent,
    this.eventType,
    this.eventDate,
    this.eventLocation,
    this.isFree,
    required this.attendeeCount,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      if (date is DateTime) return date;
      return DateTime.tryParse(date.toString()) ?? DateTime.now();
    }

    return Post(
      id: json['id'] as String? ?? json['postId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'User',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? json['text'] as String? ?? '',
      scope: json['scope'] as String? ?? 'local',
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String? ?? 'image',
      createdAt: parseDate(json['createdAt']),
      likeCount: json['likeCount'] as int? ?? 0,
      commentCount: json['commentCount'] as int? ?? 0,
      latitude: (json['latitude'] as num?)?.toDouble() ??
          (json['location']?['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ??
          (json['location']?['lng'] as num?)?.toDouble(),
      city: json['city'] as String? ?? json['location']?['name'] as String?,
      country: json['country'] as String?,
      category: json['category'] as String? ?? 'General',
      authorProfileImage: json['authorProfileImage'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isEvent: json['isEvent'] as bool? ?? false,
      eventType: json['eventType'] as String?,
      eventDate: json['eventDate'] != null ? parseDate(json['eventDate']) : null,
      eventLocation: json['eventLocation'] as String?,
      isFree: json['isFree'] as bool?,
      attendeeCount: json['attendeeCount'] as int? ?? 0,
    );
  }

  factory Post.fromMap(Map<String, dynamic> map) => Post.fromJson(map);


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'authorName': authorName,
      'title': title,
      'body': body,
      'scope': scope,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': createdAt.toIso8601String(),
      'likeCount': likeCount,
      'commentCount': commentCount,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'country': country,
      'category': category,
      'authorProfileImage': authorProfileImage,
      'thumbnailUrl': thumbnailUrl,
      'isEvent': isEvent,
      'eventType': eventType,
      'eventDate': eventDate?.toIso8601String(),
      'eventLocation': eventLocation,
      'isFree': isFree,
      'attendeeCount': attendeeCount,
    };
  }
}