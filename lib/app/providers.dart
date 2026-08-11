import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/database.dart';
import '../data/push/push_service.dart';
import '../data/api/api_client.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/contacts_repository.dart';

/// Single database instance for the app.
final dbProvider = Provider<KalisiDb>((ref) {
  final db = KalisiDb();
  ref.onDispose(db.close);
  return db;
});

/// API client.
final apiProvider = Provider<ApiClient>((ref) => ApiClient());

/// Auth repository (identity creation, login).
final authRepoProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dbProvider), ref.watch(apiProvider));
});

/// Message repository (send/receive encrypted messages).
final messageRepoProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(ref.watch(dbProvider), ref.watch(apiProvider));
});

/// Contacts repository (add friend, requests).
final contactsRepoProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(ref.watch(dbProvider), ref.watch(apiProvider));
});

/// Background poller: every few seconds, fetch new messages for the active persona.
/// Kept alive as long as something watches it (the home screen does).
final pollerProvider = Provider<Poller>((ref) {
  final poller = Poller(ref);
  ref.onDispose(poller.stop);
  return poller;
});

/// Contact id of the chat currently on screen (no alerts for it).
final openChatIdProvider = StateProvider<String?>((ref) => null);

class Poller {
  final Ref _ref;
  Timer? _timer;
  bool _busy = false;
  Poller(this._ref);

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pop up an alert (with vibration) for the newest arrived message,
  /// unless that chat is already open on screen.
  Future<void> _alert(dynamic me) async {
    try {
      final db = _ref.read(dbProvider);
      final latest = await db.latestIncoming(me.id);
      if (latest == null) return;
      final openId = _ref.read(openChatIdProvider);
      if (openId != null && openId == latest.contactId) return;

      final contact = await db.contactById(latest.contactId);
      final who = contact?.name ?? 'New message';
      final body = switch (latest.kind) {
        'img' => '📷 Photo',
        'voice' => '🎤 Voice message',
        _ => (latest.body ?? '').isEmpty ? 'New message' : latest.body!,
      };
      await PushService.showMessage(
        title: who,
        body: body.length > 80 ? '${body.substring(0, 80)}…' : body,
        id: latest.contactId.hashCode,
      );
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final me = await _ref.read(dbProvider).activePersona();
      if (me != null) {
        final received = await _ref.read(messageRepoProvider).poll(me);
        if (received > 0) await _alert(me);
      }
    } catch (_) {
      // network hiccups are fine; try again next tick
    } finally {
      _busy = false;
    }
  }
}

/// The currently active persona (null → show onboarding).
final activePersonaProvider = StreamProvider<Persona?>((ref) {
  // Live: any change to the persona row (name, avatar) updates every screen.
  ref.watch(authStateProvider);
  return ref.watch(dbProvider).watchActivePersona();
});

/// Bumped whenever auth changes (create/switch/logout) to refresh dependents.
final authStateProvider = StateProvider<int>((ref) => 0);

/// Theme mode — persisted lightly; defaults to light like the web.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);
