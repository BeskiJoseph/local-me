import 'package:flutter/material.dart';
import '../../screens/personal_account.dart';

/// Shared navigation helpers used across the app.
///
/// Replaces duplicate `_navigateToUserProfile()` implementations from:
/// - `widgets/post_card.dart`
/// - `screens/post_detail_screen.dart`
/// - `screens/Event post card.dart`

class NavigationUtils {
  NavigationUtils._(); // Prevent instantiation

  /// Navigate to a user's profile screen.
  ///
  /// [context] — BuildContext for navigation.
  /// [userId] — The ID of the user whose profile to view.
  static void navigateToProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAccount(userId: userId),
      ),
    );
  }
}
