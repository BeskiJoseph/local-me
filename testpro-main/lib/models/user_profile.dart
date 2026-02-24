class UserProfile {
  final String id;
  final String email;
  final String username;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? location;
  final String? dob;
  final String? phone;
  final String? gender;
  final String? about;
  final String? profileImageUrl;
  final int subscribers;
  final int followingCount;
  final int contents;

  UserProfile({
    required this.id,
    required this.email,
    required this.username,
    this.displayName,
    required this.firstName,
    required this.lastName,
    required this.location,
    required this.dob,
    required this.phone,
    required this.gender,
    required this.about,
    required this.profileImageUrl,
    required this.subscribers,
    required this.followingCount,
    required this.contents,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['uid'] as String? ?? json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      location: json['location'] as String?,
      dob: json['dob'] as String?,
      phone: json['phone'] as String?,
      gender: json['gender'] as String?,
      about: json['about'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      subscribers: json['subscribers'] as int? ?? 0,
      followingCount: json['followingCount'] as int? ?? 0,
      contents: json['contents'] as int? ?? 0,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) => UserProfile.fromJson(map);


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'location': location,
      'dob': dob,
      'phone': phone,
      'gender': gender,
      'about': about,
      'profileImageUrl': profileImageUrl,
      'subscribers': subscribers,
      'followingCount': followingCount,
      'contents': contents,
    };
  }
}
