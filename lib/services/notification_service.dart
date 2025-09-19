import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'supabase_service.dart';
import '../screens/home_screen.dart'; // للوصول إلى مفتاح HomeScreen
import 'dart:convert';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final SupabaseService _supabaseService = SupabaseService();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // --- إضافة: متغير لتخزين مفتاح الملاح ---
  GlobalKey<NavigatorState>? _navigatorKey;

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey; // تخزين المفتاح عند التهيئة
    await _requestPermissions();
    await _getTokenAndSave();
    _firebaseMessaging.onTokenRefresh.listen((token) {
      _supabaseService.saveDeviceToken(token);
    });
    await _setupForegroundNotifications();
    _setupInteractionListeners();
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true, announcement: false, badge: true, carPlay: false,
      criticalAlert: false, provisional: false, sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
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
      }
    } catch (e) {
      debugPrint("Failed to get FCM token: $e");
    }
  }

  Future<void> _setupForegroundNotifications() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', 'High Importance Notifications',
      description: 'This channel is used for important notifications.', importance: Importance.max,
    );

    await _localNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    await _localNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      // --- تعديل: معالجة الضغط على الإشعار المحلي (عندما يكون التطبيق في المقدمة) ---
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null && details.payload!.isNotEmpty) {
          _handleNavigation(RemoteMessage.fromMap(json.decode(details.payload!)));
        }
      },
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && !kIsWeb && android != null) {
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(channel.id, channel.name, channelDescription: channel.description, icon: android.smallIcon),
          ),
          // --- إضافة: تمرير بيانات الرسالة كاملة كـ payload ---
          payload: json.encode(message.toMap()),
        );
      }
    });
  }

  void _setupInteractionListeners() {
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) _handleNavigation(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNavigation);
  }

  // ✅ --- (تعديل): دالة معالجة التوجيه أصبحت أكثر ذكاءً ---
  // الآن تقوم بتمرير نوع الإشعار ومعرّف المشروع إلى الواجهة الرئيسية لاتخاذ الإجراء المناسب.
  void _handleNavigation(RemoteMessage message) {
    debugPrint("Notification tapped with data: ${message.data}");
    final data = message.data;
    final String? type = data['type'];
    final String? projectId = data['project_id'];

    if (_navigatorKey?.currentState != null && projectId != null) {
      // استخدام المفتاح العام للوصول إلى حالة HomeScreen وتوجيهها
      final homeScreenState = homeScreenKey.currentState;
      if (homeScreenState != null) {
        homeScreenState.handleNotificationNavigation(type, projectId);
      }
    }
  }
}
