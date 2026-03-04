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
import 'services/backend_service.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/notification_data_service.dart';
import 'config/app_theme.dart';
import 'core/session/user_session.dart';
import 'services/socket_service.dart';
import 'core/state/feed_session.dart';
import 'core/auth/auth_event_stream.dart';
import 'services/connectivity_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await NotificationService.initialize();
      NotificationDataService.initialize();
      ConnectivityService.initialize();
      await BackendService.validateServer();
      
      if (!kDebugMode) {
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
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

      SocketService.init();
      runApp(const MyApp());
    },
    (error, stackTrace) {
      if (!kDebugMode) {
        FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
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

    _connectivitySub = ConnectivityService.connectivityStream.listen((connected) {
      if (!connected) {
        ConnectivityService.showOfflineBanner(navigatorKey.currentContext!);
      } else {
        ConnectivityService.hideOfflineBanner(navigatorKey.currentContext!);
      }
    });
  }

  void _handleAuthFailure() {
    debugPrint('🚨 Global Auth Failure detected! Redirecting to login.');
    AuthService.signOut();
    UserSession.clear();
    FeedSession.instance.reset();
    
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
              FeedSession.instance.reset();
              return const HomeScreen();
            } else {
              UserSession.clear();
              FeedSession.instance.reset();
            }
          }
          return const WelcomeScreen();
        },
      ),
    );
  }
}
