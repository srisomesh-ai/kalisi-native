import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';

/// Handles a message that arrives while the app is in the background/terminated.
/// Must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // The server sends a generic "New message" push (content stays private).
  // The system tray shows it automatically for notification-type payloads.
}

/// Firebase options for messenger-app-4235 (from google-services.json).
const _kFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDhhT8XMPzMT0x5lOG1qoRKQPapgKda-XQ',
  appId: '1:834490403244:android:469068d793e3963ede9209',
  messagingSenderId: '834490403244',
  projectId: 'messenger-app-4235',
  storageBucket: 'messenger-app-4235.firebasestorage.app',
);

class PushService {
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// Initialize Firebase + local notifications. Safe to call once at startup.
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      await Firebase.initializeApp(options: _kFirebaseOptions);

      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      // local notifications channel (Android)
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _local.initialize(initSettings);

      final channel = AndroidNotificationChannel(
        'kalisi_messages',
        'Messages',
        description: 'New message alerts',
        importance: Importance.high,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 220, 120, 220]),
        playSound: true,
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // permission (Android 13+ / iOS)
      await FirebaseMessaging.instance.requestPermission();

      // show a heads-up notification when a message arrives in foreground
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) {
          _local.show(
            n.hashCode,
            n.title ?? 'Kalisi',
            n.body ?? 'New message',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'kalisi_messages',
                'Messages',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      });
    } catch (_) {
      // Firebase not available (e.g. no google-services in a dev build) — ignore.
    }
  }

  /// Show a local alert for a message that arrived while the app was polling.
  /// Falls back to a plain vibration if notifications aren't available.
  static Future<void> showMessage({
    required String title,
    required String body,
    int? id,
  }) async {
    try {
      await _local.show(
        id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kalisi_messages',
            'Messages',
            channelDescription: 'New message alerts',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 220, 120, 220]),
            ticker: 'New message',
          ),
        ),
      );
    } catch (_) {
      // notifications unavailable — at least buzz
      try {
        HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  /// Fetch the device FCM token and register it with the server for [kalId].
  static Future<void> registerToken(
      ApiClient api, String kalId, String userToken) async {
    try {
      final fcm = await FirebaseMessaging.instance.getToken();
      if (fcm == null || fcm.isEmpty) return;
      await api.fcmRegister(kalId: kalId, token: userToken, fcmToken: fcm);
      // keep server in sync if the token rotates
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        api.fcmRegister(kalId: kalId, token: userToken, fcmToken: t);
      });
    } catch (_) {}
  }
}
