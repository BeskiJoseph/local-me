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
  final DateTime? eventStartDate;
  final DateTime? eventEndDate;
  final String? eventType;
  final String? computedStatus; // 'active' or 'archived'
  final String? eventLocation;
  final bool? isFree;
  final int attendeeCount;
  final bool isLiked;
  final double? distance; // Distance from user in km
  final double? trendingScore; // For global feed trending sort
  final int viewCount; // View count for posts
  final bool isFollowing; // Whether current user follows author

  Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.scope,
    this.mediaUrl, // Changed from required to optional based on toJson and fromJson
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
    this.isEvent = false,
    this.eventStartDate,
    this.eventEndDate,
    this.eventType,
    this.computedStatus,
    this.eventLocation,
    this.isFree,
    required this.attendeeCount,
    this.isLiked = false,
    this.distance,
    this.trendingScore,
    this.viewCount = 0,
    this.isFollowing = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic date) {
      if (date == null) return DateTime.now();
      if (date is DateTime) return date;
      if (date is String) return DateTime.tryParse(date) ?? DateTime.now();
      if (date is Map && date.containsKey('_seconds')) {
         return DateTime.fromMillisecondsSinceEpoch(date['_seconds'] * 1000);
      }
      return DateTime.now();
    }

    // Defensive check for location object vs string
    final locationData = json['location'];
    Map<String, dynamic>? locationMap;
    if (locationData is Map<String, dynamic>) {
       locationMap = locationData;
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
          (locationMap?['lat'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble() ??
          (locationMap?['lng'] as num?)?.toDouble(),
      city: json['city'] as String? ?? locationMap?['name'] as String? ?? (locationData is String ? locationData : null),
      country: json['country'] as String?,
      category: json['category'] as String? ?? 'General',
      authorProfileImage: json['authorProfileImage'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isEvent: (json['isEvent'] == true) || 
          (json['category'] as String? ?? '').toLowerCase() == 'events',
      
      eventStartDate: json['eventStartDate'] != null 
          ? parseDate(json['eventStartDate'])
          : parseDate(json['eventDate']),
          
      eventEndDate: json['eventEndDate'] != null ? parseDate(json['eventEndDate']) : null,
      eventType: json['eventType'] as String?,
      computedStatus: json['computedStatus'] as String?,
      
      eventLocation: json['eventLocation'] as String?,
      isFree: json['isFree'] as bool?,
      attendeeCount: json['attendeeCount'] as int? ?? 0,
      isLiked: json['isLiked'] ?? false,
      distance: (json['distance'] as num?)?.toDouble(),
      trendingScore: (json['trendingScore'] as num?)?.toDouble(),
      viewCount: json['viewCount'] as int? ?? 0,
      isFollowing: json['isFollowing'] ?? false,
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
      'eventStartDate': eventStartDate?.toIso8601String(),
      'eventEndDate': eventEndDate?.toIso8601String(),
      'eventType': eventType,
      'computedStatus': computedStatus,
      'eventLocation': eventLocation,
      'isFree': isFree,
      'attendeeCount': attendeeCount,
      'isLiked': isLiked,
      'viewCount': viewCount,
      'isFollowing': isFollowing,
    };
  }

  Post copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? title,
    String? body,
    String? authorProfileImage,
    String? scope,
    String? mediaUrl,
    String? mediaType,
    DateTime? createdAt,
    int? likeCount,
    int? commentCount,
    double? latitude,
    double? longitude,
    String? city,
    String? country,
    String? category,
    String? thumbnailUrl,
    bool? isEvent,
    DateTime? eventStartDate,
    DateTime? eventEndDate,
    String? eventType,
    String? computedStatus,
    String? eventLocation,
    bool? isFree,
    int? attendeeCount,
    bool? isLiked,
    double? distance,
    double? trendingScore,
    int? viewCount,
    bool? isFollowing,
  }) {
    return Post(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      title: title ?? this.title,
      body: body ?? this.body,
      authorProfileImage: authorProfileImage ?? this.authorProfileImage,
      scope: scope ?? this.scope,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      city: city ?? this.city,
      country: country ?? this.country,
      category: category ?? this.category,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      isEvent: isEvent ?? this.isEvent,
      eventStartDate: eventStartDate ?? this.eventStartDate,
      eventEndDate: eventEndDate ?? this.eventEndDate,
      eventType: eventType ?? this.eventType,
      computedStatus: computedStatus ?? this.computedStatus,
      eventLocation: eventLocation ?? this.eventLocation,
      isFree: isFree ?? this.isFree,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      isLiked: isLiked ?? this.isLiked,
      distance: distance ?? this.distance,
      trendingScore: trendingScore ?? this.trendingScore,
      viewCount: viewCount ?? this.viewCount,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}
