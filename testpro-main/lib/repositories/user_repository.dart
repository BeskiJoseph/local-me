import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';
import '../models/signup_data.dart';

/// Repository for handling User Profile operations.
/// Accepts [FirebaseFirestore] and [FirebaseAuth] for dependency injection.
class UserRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  UserRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Stream<UserProfile?> userProfileStream(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromMap(doc.id, doc.data()!);
    });
  }

  Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(doc.id, doc.data()!);
  }

  Future<void> createUserProfile({
    required User user,
    required SignupData data,
    String? profileImageUrl,
  }) async {
    final profile = UserProfile(
      id: user.uid,
      email: user.email ?? data.email ?? '',
      username: data.username ?? user.displayName ?? '',
      firstName: data.firstName,
      lastName: data.lastName,
      location: data.location,
      dob: data.dob,
      phone: null,
      gender: null,
      about: null,
      profileImageUrl: profileImageUrl ?? user.photoURL,
      subscribers: 0,
      followingCount: 0,
      contents: 0,
    );

    await _db.collection('users').doc(user.uid).set(profile.toMap());
  }

  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? about,
    String? profileImageUrl,
  }) async {
    final Map<String, dynamic> data = {};
    if (displayName != null) {
      data['username'] = displayName;
    }
    if (about != null) {
      data['about'] = about;
    }
    if (profileImageUrl != null) {
      data['profileImageUrl'] = profileImageUrl;
    }

    if (data.isEmpty) return;

    await _db.collection('users').doc(userId).update(data);
  }

  Future<void> syncGoogleUser(User user) async {
    final userDoc = _db.collection('users').doc(user.uid);
    final snapshot = await userDoc.get();

    if (!snapshot.exists) {
      // Create new profile
      final profile = UserProfile(
        id: user.uid,
        email: user.email ?? '',
        username: user.displayName ?? 'User',
        firstName: null,
        lastName: null,
        location: null,
        dob: null,
        phone: null,
        gender: null,
        about: null,
        profileImageUrl: user.photoURL,
        subscribers: 0,
        followingCount: 0,
        contents: 0,
      );
      await userDoc.set(profile.toMap());
    } else {
      // Update existing profile photo if changed (optional, but good for sync)
      if (user.photoURL != null) {
        await userDoc.update({'profileImageUrl': user.photoURL});
      }
    }
  }

  Future<void> incrementContentCount(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    // Use transaction for atomic update
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) return;
      final current = snapshot.get('contents') as int? ?? 0;
      transaction.update(userRef, {'contents': current + 1});
    }).catchError((e, stack) {
      if (kDebugMode) {
        print("Increment Content Count Error: $e");
        print("Stack trace: $stack");
      }
    });
  }

  Future<void> recalculateUserStats(String userId) async {
    try {
      // Count actual posts
      final postsSnapshot = await _db
          .collection('posts')
          .where('authorId', isEqualTo: userId)
          .get();
      final contentCount = postsSnapshot.docs.length;

      // Count actual followers
      final followersSnapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('followers')
          .get();
      final subscriberCount = followersSnapshot.docs.length;

      // Get current user data or create new profile
      final userDoc = await _db.collection('users').doc(userId).get();
      
      if (!userDoc.exists) {
        // Create a basic profile if it doesn't exist
        final user = _auth.currentUser;
        await _db.collection('users').doc(userId).set({
          'email': user?.email ?? '',
          'username': user?.displayName ?? 'User',
          'firstName': null,
          'lastName': null,
          'location': null,
          'dob': null,
          'phone': null,
          'gender': null,
          'about': null,
          'profileImageUrl': user?.photoURL,
          'contents': contentCount,
          'subscribers': subscriberCount,
        });
      } else {
        // Update existing profile with correct counts
        await _db.collection('users').doc(userId).update({
          'contents': contentCount,
          'subscribers': subscriberCount,
        });
      }

      if (kDebugMode) {
        print("Recalculated stats for $userId: $contentCount contents, $subscriberCount subscribers");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error recalculating stats: $e");
      }
      rethrow;
    }
  }
}
