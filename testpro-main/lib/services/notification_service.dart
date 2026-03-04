import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import '../screens/post_detail_screen.dart';
import '../main.dart';
import 'backend_service.dart';
import 'notification_data_service.dart';

/// Top-level background message handler for FCM.
/// Must be top-level to work in release mode.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) print('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Request permission for iOS/Android 13+
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (kDebugMode) print('User granted permission');
      
      // Get Initial FCM Token
      String? token = await _messaging.getToken();
      if (token != null) {
        _saveTokenToBackend(token);
      }
    }

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(initSettings);

    // Handle incoming messages (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Increment local badge without fetching backend
      NotificationDataService.unreadCount.value++;
      _showLocalNotification(message);
    });

    // Handle push tapped in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // Handle push tapped from killed state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Handle token refresh (Critical for production stability)
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _saveTokenToBackend(newToken);
    });

    // Register Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final postId = data['postId'] as String?;
    
    if (postId != null && navigatorKey.currentContext != null) {
      Navigator.push(
        navigatorKey.currentContext!,
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
      );
    }
  }

  static void _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      details,
    );
  }

  static Future<void> _saveTokenToBackend(String token) async {
    try {
      await BackendService.updateProfile({
        'fcmToken': token,
      });
      if (kDebugMode) debugPrint('FCM Token synced to backend');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to sync FCM token: $e');
    }
  }

  static Future<void> updateToken() async {
    String? token = await _messaging.getToken();
    if (token != null) {
      _saveTokenToBackend(token);
    }
  }
}
