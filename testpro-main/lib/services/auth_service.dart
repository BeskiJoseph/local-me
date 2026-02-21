import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = kIsWeb 
    ? GoogleSignIn(clientId: '869861670780-64hg1hemqte17odvlu6r6gk3mikdbdps.apps.googleusercontent.com') 
    : GoogleSignIn();

  // Get current user
  static User? get currentUser => _auth.currentUser;

  // Check if user is logged in
  static bool get isLoggedIn => _auth.currentUser != null;

  // Get ID token
  static Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _auth.currentUser?.getIdToken(forceRefresh);
  }

  // Auth state changes stream
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  static Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with email and password
  static Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with Google
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      GoogleSignInAccount? googleUser;
      
      if (kIsWeb) {
        // For web, suppress the deprecation warning
        // The warning is about using signIn() on web, but it still works
        // A future migration to google_identity_services with renderButton is recommended
        try {
          googleUser = await _googleSignIn.signInSilently();
        } catch (e) {
        }
        
        if (googleUser == null) {
          try {
            googleUser = await _googleSignIn.signIn();
          } catch (e) {
            // popup_closed is expected when user cancels
            if (e.toString().contains('popup_closed')) {
              return null;
            }
            rethrow;
          }
        }
      } else {
        // For mobile, use regular sign-in
        googleUser = await _googleSignIn.signIn();
      }
      
      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      return result;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error during sign out: $e');
      }
      // Rethrow to allow UI to handle the error
      rethrow;
    }
  }

  // Reset password
  static Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Password reset error: ${e.code} - ${e.message}');
      }
      rethrow;
    }
  }

  // Update user profile
  static Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      await _auth.currentUser?.updateDisplayName(displayName);
      await _auth.currentUser?.updatePhotoURL(photoURL);
      // Enterprise Polish: Ensure local currentUser object is reloaded with new metadata
      await _auth.currentUser?.reload();
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('Profile update error: ${e.code} - ${e.message}');
      }
      rethrow;
    }
  }
  // Reload user
  static Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } on FirebaseAuthException {
    }
  }

  // Send email verification
  static Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException {
      rethrow;
    }
  }
}
