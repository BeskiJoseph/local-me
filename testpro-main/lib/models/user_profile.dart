class UserProfile {
  final String id;
  final String email;
  final String username;
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

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      email: data['email'] as String? ?? '',
      username: data['username'] as String? ?? '',
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      location: data['location'] as String?,
      dob: data['dob'] as String?,
      phone: data['phone'] as String?,
      gender: data['gender'] as String?,
      about: data['about'] as String?,
      profileImageUrl: data['profileImageUrl'] as String?,
      subscribers: data['subscribers'] as int? ?? 0,
      followingCount: data['followingCount'] as int? ?? 0,
      contents: data['contents'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'username': username,
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

