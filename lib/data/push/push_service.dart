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

  /// Decides whether a push arriving while the app is open should be shown.
  /// Set by the app so this class stays free of app state.
  static bool Function(Map<String, dynamic> data)? suppress;

  /// Called with the sender's KAL-id when a notification is tapped, so the
  /// app can open that conversation.
  static void Function(String fromKalId)? onOpenChat;

  /// Called when a call push arrives, so the app can start polling for the
  /// offer immediately rather than waiting for the next tick.
  static void Function()? onIncomingCall;

  /// A tap that arrived before the app was ready to handle it.
  static String? _pendingOpen;

  /// Handle a tap that came in during startup.
  static void drainPendingOpen() {
    final p = _pendingOpen;
    if (p != null && onOpenChat != null) {
      _pendingOpen = null;
      onOpenChat!(p);
    }
  }

  static void _handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (onOpenChat != null) {
      onOpenChat!(payload);
    } else {
      _pendingOpen = payload;   // app not ready yet
    }
  }

  /// Clear the notifications for one chat — used once its messages are read.
  static Future<void> clearFor(String contactKey) async {
    try {
      await _local.cancel(contactKey.hashCode);
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      await _local.cancelAll();
    } catch (_) {}
  }

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
      await _local.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (r) => _handleTap(r.payload),
      );

      // tapped while the app was in the background
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        _handleTap(msg.data['from']?.toString());
      });

      // tapped while the app was closed entirely
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _pendingOpen = initial.data['from']?.toString();
      }

      // Calls ring louder and longer than a message alert.
      final callChannel = AndroidNotificationChannel(
        'kalisi_calls',
        'Calls',
        description: 'Incoming voice calls',
        importance: Importance.max,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 700, 400, 700, 400, 700]),
        playSound: true,
      );

      final channel = AndroidNotificationChannel(
        'kalisi_messages_v2',
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
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(callChannel);

      // permission (Android 13+ / iOS)
      await FirebaseMessaging.instance.requestPermission();

      // show a heads-up notification when a message arrives in foreground
      FirebaseMessaging.onMessage.listen((msg) {
        if (msg.data['type']?.toString() == 'call') onIncomingCall?.call();
        final n = msg.notification;
        // The app is open. Stay quiet if the message is for the chat already
        // on screen, or for a chat the user muted — otherwise it would pop a
        // banner over the very conversation being read.
        final isCall = msg.data['type']?.toString() == 'call';
        if (!isCall && suppress?.call(msg.data) == true) return;
        if (n != null) {
          _local.show(
            n.hashCode,
            n.title ?? 'Kalisi',
            n.body ?? 'New message',
            payload: msg.data['from']?.toString(),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'kalisi_messages_v2',
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
    String? fromKalId,
  }) async {
    try {
      await _local.show(
        id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'kalisi_messages_v2',
            'Messages',
            channelDescription: 'New message alerts',
            importance: Importance.high,
            priority: Priority.high,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 220, 120, 220]),
            playSound: true,
            ticker: 'New message',
          ),
        ),
        payload: fromKalId,
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
