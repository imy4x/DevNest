import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'supabase_service.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final SupabaseService _supabaseService = SupabaseService();

  // Singleton pattern to ensure only one instance of NotificationService is created
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  FlutterLocalNotificationsPlugin get localNotificationsPlugin => _localNotificationsPlugin;


  // Local notifications plugin
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Request permissions
    await _requestPermissions();

    // 2. Get and save FCM token
    await _getTokenAndSave();

    // 3. Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((token) {
      _supabaseService.saveDeviceToken(token);
    });

    // 4. Setup foreground notification handling
    await _setupForegroundNotifications();

    // 5. Setup listeners for when a notification is tapped
    _setupInteractionListeners();
  }

  Future<void> _requestPermissions() async {
  NotificationSettings settings = await _firebaseMessaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    debugPrint('User granted notification permission');
  } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
    debugPrint('User granted provisional notification permission');
  } else {
    debugPrint('User declined or has not accepted notification permission');
  }
}


  Future<void> _getTokenAndSave() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        debugPrint("FCM Token: $token");
        await _supabaseService.saveDeviceToken(token);
      } else {
        debugPrint("FCM Token is null.");
      }
    } catch (e) {
      debugPrint("Failed to get FCM token: $e");
    }
  }

  Future<void> _setupForegroundNotifications() async {
    // Create a channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.', // description
      importance: Importance.max,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialize the plugin for iOS and Android
    await _localNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    // Listen for incoming messages while the app is in the foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && !kIsWeb) {
        // If it's an Android notification with a channel, display it
        if (android != null) {
          _localNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: android.smallIcon,
              ),
            ),
          );
        }
        // You can add iOS foreground notification logic here if needed
      }
    });
  }

  void _setupInteractionListeners() {
    // Handles when the app is opened from a terminated state by a notification
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        // Handle initial message
        _handleMessageOpened(message);
      }
    });

    // Handles when the app is opened from the background by a notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpened);
  }
  void sendTestNotification() {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.max,
  );

  final notification = RemoteNotification(
    title: 'اختبار إشعار',
    body: 'هذا إشعار foreground للتجربة',
  );

  _localNotificationsPlugin.show(
    0,
    notification.title,
    notification.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

  void _handleMessageOpened(RemoteMessage message) {
    debugPrint("Notification tapped with data: ${message.data}");
    // Here you can navigate to a specific screen based on message.data
  }
}