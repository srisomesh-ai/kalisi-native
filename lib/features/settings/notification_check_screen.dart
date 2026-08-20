import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';

/// Shows exactly which part of the notification chain is failing.
class NotificationCheckScreen extends ConsumerStatefulWidget {
  const NotificationCheckScreen({super.key});
  @override
  ConsumerState<NotificationCheckScreen> createState() =>
      _NotificationCheckScreenState();
}

class _NotificationCheckScreenState
    extends ConsumerState<NotificationCheckScreen> {
  bool _busy = false;
  Map<String, dynamic>? _server;
  String? _deviceToken;
  bool? _permission;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _testResult = null;
    });

    // what the phone says
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      _permission =
          settings.authorizationStatus == AuthorizationStatus.authorized;
    } catch (_) {
      _permission = false;
    }
    try {
      _deviceToken = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      _deviceToken = null;
    }

    // make sure the server has our current token before asking it
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me != null && _deviceToken != null) {
      try {
        await ref.read(apiProvider).fcmRegister(
              kalId: me.kalId,
              token: me.token,
              fcmToken: _deviceToken!,
            );
      } catch (_) {}
      try {
        _server = await ref
            .read(apiProvider)
            .pushCheck(kalId: me.kalId, token: me.token);
      } catch (e) {
        _server = {'error': '$e'};
      }
    }

    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendTest() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    setState(() {
      _busy = true;
      _testResult = null;
    });
    try {
      final res =
          await ref.read(apiProvider).pushTest(kalId: me.kalId, token: me.token);
      final sent = res['sent'];
      if (sent is Map && sent['ok'] == true) {
        _testResult = 'Sent — the notification should appear in a moment.';
      } else if (sent is Map) {
        _testResult = 'Failed: ${sent['why'] ?? sent['attempts'] ?? sent}';
      } else {
        _testResult = 'Failed: $sent';
      }
    } catch (e) {
      _testResult = 'Failed: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _localTest() async {
    try {
      await FlutterLocalNotificationsPlugin().show(
        999,
        'Kalisi',
        'This is a local test notification',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'kalisi_messages_v2',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      setState(() => _testResult =
          'Local notification sent — if you see nothing, notifications are '
          'blocked for Kalisi in Android settings.');
    } catch (e) {
      setState(() => _testResult = 'Local notification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final srv = _server ?? const {};
    final ready = srv['ready'] == true;

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Notification check',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        actions: [
          IconButton(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child:
                  Center(child: CircularProgressIndicator(color: KColors.teal)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ready ? KColors.okBg : KColors.amberBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                      ready
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: ready
                          ? const Color(0xFF1E8449)
                          : KColors.amberInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ready
                          ? 'Everything is set up. Notifications should arrive.'
                          : 'Something in the chain is not ready — see below.',
                      style: TextStyle(
                          color: ready
                              ? const Color(0xFF1E8449)
                              : KColors.amberInk,
                          fontSize: 13.5,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _Section('ON THIS PHONE'),
            _Row(
              label: 'Notification permission',
              ok: _permission == true,
              detail: _permission == true ? 'Allowed' : 'Not allowed',
            ),
            _Row(
              label: 'Device registered with Firebase',
              ok: _deviceToken != null,
              detail: _deviceToken == null
                  ? 'No token — Firebase did not start'
                  : '…${_deviceToken!.substring(_deviceToken!.length - 12)}',
            ),

            _Section('ON THE SERVER'),
            _Row(
              label: 'Firebase key file',
              ok: srv['key_file_valid'] == true,
              detail: srv['key_file_present'] == true
                  ? (srv['key_file_valid'] == true
                      ? 'Valid · ${srv['project_id'] ?? ''}'
                      : 'Present but not readable as JSON')
                  : 'Not found at api/fcm-key.json',
            ),
            _Row(
              label: 'Google authentication',
              ok: srv['google_auth_ok'] == true,
              detail: srv['google_auth_ok'] == true
                  ? 'Working'
                  : (srv['google_auth_hint']?.toString() ??
                      'Could not get a token'),
            ),
            _Row(
              label: 'This device known to server',
              ok: (srv['devices_registered'] ?? 0) is int &&
                  (srv['devices_registered'] ?? 0) > 0,
              detail: '${srv['devices_registered'] ?? 0} device(s)',
            ),

            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy ? null : _sendTest,
              icon: const Icon(Icons.send_rounded, size: 19),
              label: const Text('Send myself a test notification'),
              style: FilledButton.styleFrom(
                backgroundColor: KColors.teal,
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _localTest,
              icon: const Icon(Icons.notifications_active_outlined, size: 19),
              label: const Text('Test without the server'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KColors.teal,
                side: const BorderSide(color: KColors.teal),
                minimumSize: const Size.fromHeight(48),
              ),
            ),

            if (_testResult != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: s.panel2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_testResult!,
                    style: TextStyle(
                        color: s.text, fontSize: 13, height: 1.45)),
              ),
            ],

            const SizedBox(height: 26),
            _Section('IF NOTIFICATIONS STILL DO NOT ARRIVE'),
            Text(
                'Android stops background apps to save battery, and this is the '
                'most common cause. Open Settings → Apps → Kalisi → Battery and '
                'choose Unrestricted. On Samsung, also check Device care → '
                'Battery → Background usage limits and make sure Kalisi is not '
                'listed under Sleeping or Deep sleeping apps.',
                style:
                    TextStyle(color: s.muted, fontSize: 13, height: 1.55)),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Text(title,
          style: TextStyle(
              color: s.faint,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7)),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final bool ok;
  final String detail;
  const _Row({required this.label, required this.ok, required this.detail});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: ok ? const Color(0xFF27AE60) : KColors.danger, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: s.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detail,
                    style: TextStyle(color: s.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
