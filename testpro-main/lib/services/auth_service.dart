import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../core/state/feed_session.dart';
import '../core/session/user_session.dart';
import 'backend_service.dart';
import 'socket_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = kIsWeb
      ? GoogleSignIn(
          clientId:
              '869861670780-64hg1hemqte17odvlu6r6gk3mikdbdps.apps.googleusercontent.com',
        )
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
  static Future<UserCredential?> signUpWithEmail(
    String email,
    String password,
  ) async {
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
  static Future<UserCredential?> signInWithEmail(
    String email,
    String password,
  ) async {
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
        try {
          googleUser = await _googleSignIn.signInSilently();
        } catch (e) {}

        if (googleUser == null) {
          try {
            googleUser = await _googleSignIn.signIn();
          } catch (e) {
            if (e.toString().contains('popup_closed')) {
              return null;
            }
            rethrow;
          }
        }
      } else {
        googleUser = await _googleSignIn.signIn();
      }

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

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

  // ──────────────────────────────────────────────
  // SIGN OUT — Full Session Teardown
  // Order matters:
  //   1. Kill real-time connections (socket)
  //   2. Clear in-memory session state
  //   3. Sign out of identity providers
  // ──────────────────────────────────────────────
  static Future<void> signOut() async {
    try {
      // 1. Disconnect real-time socket (prevents ghost events after logout)
      SocketService.dispose();

      // 2. Clear all in-memory session state
      UserSession.clear();
      BackendClient.clearSession();
      FeedSession.instance.resetAll();

      // 3. Sign out of identity providers
      await _googleSignIn.signOut();
      await _auth.signOut();

      if (kDebugMode) debugPrint('✅ Full logout complete');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error during sign out: $e');
      }
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
  static Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      await _auth.currentUser?.updateDisplayName(displayName);
      await _auth.currentUser?.updatePhotoURL(photoURL);
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
    } on FirebaseAuthException {}
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
