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
import 'package:testpro/core/state/post_state.dart';
import 'package:testpro/services/post_service.dart';
import 'package:testpro/services/interaction_service.dart';

void main() {
  final container = ProviderContainer();
  GlobalProviderContainer.initialize(container);

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _authSub;
  StreamSubscription? _eventSub;
  StreamSubscription? _connectivitySub;
  Timer? _memoryCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startMemoryMonitoring();
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
      final context = ErrorHandler.navigatorKey.currentContext;
      if (context == null) return;
      if (!connected) {
        ConnectivityService.showOfflineBanner(context);
      } else {
        ConnectivityService.hideOfflineBanner(context);
      }
    });
  }

  void _startMemoryMonitoring() {
    _memoryCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkMemoryPressure();
    });
  }

  void _checkMemoryPressure() {
    try {
      final imageCache = PaintingBinding.instance.imageCache;
      final currentSize = imageCache.currentSize;
      final maxSize = imageCache.maximumSize;
      if (maxSize > 0 && currentSize / maxSize > 0.7) {
        _triggerMemoryCleanup();
      }
    } catch (e) {}
  }

  void _triggerMemoryCleanup() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    PostService.clearInteractionCache();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _triggerMemoryCleanup();
      clearSessionBuffer();
    }
  }

  void clearSessionBuffer() {
    try {
      final container = GlobalProviderContainer.instance;
      if (container != null) {
        final notifier = container.read(postStoreProvider.notifier);
        notifier.clearSessionBuffer();
      }
    } catch (e) {}
  }

  void _handleAuthFailure() {
    AuthService.signOut();
    UserSession.clear();
    FeedSession.instance.resetAll();
    SocketService.dispose();

    ErrorHandler.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _eventSub?.cancel();
    _connectivitySub?.cancel();
    _memoryCheckTimer?.cancel();
    SocketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ErrorHandler.navigatorKey,
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
