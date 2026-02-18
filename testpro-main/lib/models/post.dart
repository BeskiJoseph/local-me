import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory Post.fromMap(String id, Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    DateTime created;
    if (rawCreatedAt is Timestamp) {
      created = rawCreatedAt.toDate();
    } else if (rawCreatedAt is DateTime) {
      created = rawCreatedAt;
    } else {
      created = DateTime.tryParse(rawCreatedAt?.toString() ?? '') ?? DateTime.now();
    }

    return Post(
      id: id,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      scope: data['scope'] as String? ?? 'local',
      mediaUrl: data['mediaUrl'] as String?,
      mediaType: data['mediaType'] as String? ?? 'image',
      createdAt: created,
      likeCount: data['likeCount'] as int? ?? 0,
      commentCount: data['commentCount'] as int? ?? 0,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      city: data['city'] as String?,
      country: data['country'] as String?,
      category: data['category'] as String? ?? 'General',
      authorProfileImage: data['authorProfileImage'] as String?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      // Event fields
      isEvent: data['isEvent'] ?? false,
      eventType: data['eventType'] as String?,
      eventDate: data['eventDate'] != null 
          ? (data['eventDate'] as Timestamp).toDate() 
          : null,
      eventLocation: data['eventLocation'] as String?,
      isFree: data['isFree'] as bool?,
      attendeeCount: data['attendeeCount'] as int? ?? 0,
    );
  }

  factory Post.fromFirestore(DocumentSnapshot doc) {
    return Post.fromMap(doc.id, doc.data() as Map<String, dynamic>);
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'title': title,
      'body': body,
      'scope': scope,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': createdAt,
      'likeCount': likeCount,
      'commentCount': commentCount,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'country': country,
      'category': category,
      'authorProfileImage': authorProfileImage,
      'thumbnailUrl': thumbnailUrl,
      // Event fields
      'isEvent': isEvent,
      'eventType': eventType,
      'eventDate': eventDate != null ? Timestamp.fromDate(eventDate!) : null,
      'eventLocation': eventLocation,
      'isFree': isFree,
      'attendeeCount': attendeeCount,
    };
  }
}