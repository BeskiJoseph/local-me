import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'config/app_theme.dart';
import 'core/session/user_session.dart';
import 'services/socket_service.dart';
import 'core/state/feed_session.dart';

void main() {
  // ──────────────────────────────────────────────
  // LAYER 3: runZonedGuarded wraps EVERYTHING.
  //   ensureInitialized + Firebase.initializeApp + runApp
  //   must all be in the SAME ZONE to avoid zone mismatch.
  // ──────────────────────────────────────────────
  runZonedGuarded(
    () async {
      // 1. Framework & Firebase Core (Must be first, same zone as runApp)
      WidgetsFlutterBinding.ensureInitialized();

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // ────────────────────────────────────────────
      // 2. Crashlytics Error Routing (set up after Firebase init)
      //    Layer 1: FlutterError.onError    → Widget build errors
      //    Layer 2: PlatformDispatcher      → Platform channel + native errors
      //    Layer 3: runZonedGuarded (this zone) → Uncaught async errors
      // ────────────────────────────────────────────

      // LAYER 1: Flutter framework errors (build, layout, paint)
      if (!kDebugMode) {
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      } else {
        FlutterError.onError = (FlutterErrorDetails details) {
          FlutterError.presentError(details);
          debugPrint('🔴 Flutter Error: ${details.exceptionAsString()}');
        };
      }

      // LAYER 2: Platform channel and isolate errors
      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) {
          debugPrint('🚨 Platform Error: $error');
          debugPrint('📍 Stack: $stack');
        } else {
          FirebaseCrashlytics.instance.recordError(
            error,
            stack,
            fatal: true,
            reason: 'PlatformDispatcher.onError',
          );
        }
        return true;
      };

      // 3. Lightweight service init (safe to run before widget tree)
      await NotificationService.initialize();
      SocketService.init();

      // 4. Launch app (same zone as ensureInitialized — no mismatch)
      runApp(const MyApp());
    },
    (error, stackTrace) {
      // LAYER 3: Uncaught async errors
      if (kDebugMode) {
        debugPrint('🚨 Uncaught Async Error: $error');
        debugPrint('📍 Stack: $stackTrace');
      } else {
        FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          fatal: true,
          reason: 'Unhandled async error in runZonedGuarded',
        );
      }
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocalMe',
      theme: AppTheme.lightTheme.copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        scaffoldBackgroundColor: AppTheme.background,
      ),
      themeMode: ThemeMode.light,
      home: StreamBuilder<User?>(
        stream: AuthService.authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            final user = snapshot.data;
            if (user != null) {
              // Initialize session cache on completely fresh launches / stream re-connects
              UserSession.update(
                id: user.uid,
                name: user.displayName,
                avatar: user.photoURL,
              );
              FeedSession.instance.reset(); // Clear exclusion list for new user
              return const HomeScreen();
            } else {
              // Ensure we dump cache on sign out
              UserSession.clear();
              FeedSession.instance.reset(); // Clear exclusion list on logout
            }
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}
