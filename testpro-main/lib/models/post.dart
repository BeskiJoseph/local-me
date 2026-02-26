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
      isEvent: (json['isEvent'] == true) || 
          (json['category'] as String? ?? '').toLowerCase() == 'events',
      
      // Lazy mapping fallback for event start date on the client as well
      eventStartDate: json['eventStartDate'] != null 
          ? DateTime.parse(json['eventStartDate'])
          : (json['eventDate'] != null ? DateTime.parse(json['eventDate']) : null),
          
      eventEndDate: json['eventEndDate'] != null ? DateTime.parse(json['eventEndDate']) : null,
      eventType: json['eventType'] as String?,
      computedStatus: json['computedStatus'] as String?,
      
      eventLocation: json['eventLocation'] as String?,
      isFree: json['isFree'] as bool?,
      attendeeCount: json['attendeeCount'] as int? ?? 0,
      isLiked: json['isLiked'] ?? false,
      distance: (json['distance'] as num?)?.toDouble(),
      trendingScore: (json['trendingScore'] as num?)?.toDouble(),
      viewCount: json['viewCount'] as int? ?? 0,
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
    };
  }
}