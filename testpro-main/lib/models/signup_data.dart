class SignupData {
  String? email;
  String? password; // TODO BUG-032: Clear password immediately after Firebase auth creation to minimize in-memory exposure

  String? username;
  String? firstName;
  String? lastName;
  String?location;
  String? dob;          // ✅ Date of Birth
  double? latitude;     // ✅ Auto location
  double? longitude;
  String? profileImagePath;

  SignupData();
}
