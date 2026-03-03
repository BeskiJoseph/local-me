import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'config/app_theme.dart';
import 'core/session/user_session.dart';
import 'services/socket_service.dart';
import 'core/state/feed_session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();
  SocketService.init();

  runApp(const MyApp());
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
