import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:testpro/screens/welcome_screen.dart';
import 'package:testpro/screens/home_screen.dart';
import 'package:testpro/services/auth_service.dart';
import 'package:testpro/services/backend_service.dart';
import 'package:testpro/firebase_options.dart';
import 'package:testpro/services/notification_service.dart';
import 'package:testpro/services/notification_data_service.dart';
import 'package:testpro/config/app_theme.dart';
import 'package:testpro/core/session/user_session.dart';
import 'package:testpro/services/socket_service.dart';
import 'package:testpro/core/state/feed_session.dart';
import 'package:testpro/core/auth/auth_event_stream.dart';
import 'package:testpro/services/connectivity_service.dart';
import 'package:testpro/core/state/provider_container.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  // 🚀 Initialize Riverpod ProviderContainer for static services ABSOLUTE FIRST
  final container = ProviderContainer();
  GlobalProviderContainer.initialize(container);

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Critical: Initialize Firebase first
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 2. Non-critical: Initialize other services in parallel or background
      unawaited(
        NotificationService.initialize().then(
          (_) => NotificationDataService.initialize(),
        ),
      );
      ConnectivityService.initialize();
      unawaited(BackendService.validateServer());

      if (!kDebugMode) {
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
      } else {
        FlutterError.onError = (FlutterErrorDetails details) {
          FlutterError.presentError(details);
          debugPrint('🔴 Flutter Error: ${details.exceptionAsString()}');
        };
      }

      PlatformDispatcher.instance.onError = (error, stack) {
        if (!kDebugMode) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        } else {
          debugPrint('🚨 Platform Error: $error');
        }
        return true;
      };

      runApp(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
    },
    (error, stackTrace) {
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          fatal: true,
        );
      } else {
        debugPrint('🚨 Uncaught Async Error: $error');
      }
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _authSub;
  StreamSubscription? _eventSub;
  StreamSubscription? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _authSub = BackendService.onAuthFailure.listen((_) {
      _handleAuthFailure();
    });

    _eventSub = AuthEventStream.events.listen((event) {
      if (event.type == AuthEventType.sessionExpired) {
        _handleAuthFailure();
      }
    });

    _connectivitySub = ConnectivityService.connectivityStream.listen((
      connected,
    ) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      if (!connected) {
        ConnectivityService.showOfflineBanner(context);
      } else {
        ConnectivityService.hideOfflineBanner(context);
      }
    });
  }

  void _handleAuthFailure() {
    debugPrint('🚨 Global Auth Failure detected! Redirecting to login.');
    AuthService.signOut();
    UserSession.clear();
    FeedSession.instance.resetAll();

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _eventSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
              UserSession.update(
                id: user.uid,
                name: user.displayName,
                avatar: user.photoURL,
              );
              // Initialize Authenticated Socket
              user.getIdToken().then((token) {
                if (token != null) SocketService.init(token);
              });
              return const HomeScreen();
            } else {
              UserSession.clear();
            }
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}
