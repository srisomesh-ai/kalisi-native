import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db/database.dart';
import '../data/push/push_service.dart';
import '../data/call/call_service.dart';
import '../util/mask.dart';
import '../util/buzz.dart';
import '../features/status/status_model.dart';
import '../features/settings/backup_screen.dart';
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
  return MessageRepository(
    ref.watch(dbProvider),
    ref.watch(apiProvider),
    onTyping: (contactId) =>
        ref.read(typingProvider.notifier).mark(contactId),
    onCallSignal: (from, kind, data) async {
      final call = ref.read(callServiceProvider);
      final me = await ref.read(dbProvider).activePersona();
      if (me == null) return;
      switch (kind) {
        case 'call-offer':
          await call.onOffer(me, from, data);
          break;
        case 'call-answer':
          await call.onAnswer(data);
          break;
        case 'call-ice':
          await call.onCandidate(data);
          break;
        case 'call-end':
          await call.onRemoteEnd(data['reason']?.toString());
          break;
      }
    },
  );
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

/// The single active call (if any).
final callServiceProvider = ChangeNotifierProvider<CallService>((ref) {
  return CallService(ref.watch(dbProvider), ref.watch(apiProvider));
});

/// Who is currently typing: contactId -> when their 'typing' signal expires.
class TypingNotifier extends StateNotifier<Map<String, int>> {
  TypingNotifier() : super(const {});

  /// Someone is typing — keep it showing for a few seconds.
  void mark(String contactId) {
    state = {...state, contactId: DateTime.now().millisecondsSinceEpoch + 6000};
  }

  void clear(String contactId) {
    final m = {...state}..remove(contactId);
    state = m;
  }

  bool isTyping(String contactId) {
    final until = state[contactId];
    if (until == null) return false;
    return DateTime.now().millisecondsSinceEpoch < until;
  }
}

final typingProvider =
    StateNotifierProvider<TypingNotifier, Map<String, int>>(
        (ref) => TypingNotifier());

/// Whether the app makes its little sounds and taps.
final soundsProvider = StateProvider<bool>((ref) => true);

/// Lets any screen ask the shell to switch tabs.
final goToTabProvider = StateProvider<int?>((ref) => null);

/// Bumped by the poller so pending contact requests refresh on their own.
final requestsTickProvider = StateProvider<int>((ref) => 0);

/// KAL-id of the chat on screen, so server pushes can be matched to it.
final openChatKalIdProvider = StateProvider<String?>((ref) => null);

/// Contact id of the chat currently on screen (no alerts for it).
final openChatIdProvider = StateProvider<String?>((ref) => null);

class Poller {
  final Ref _ref;
  Timer? _timer;
  bool _busy = false;
  int _ticks = 0;
  Poller(this._ref);

  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  /// During a call, signalling needs to move quickly — poll every second.
  void setFast(bool fast) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: fast ? 500 : 3000),
      (_) => _tick(),
    );
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
      if (openId != null && openId == latest.contactId) {
        // Already looking at this chat: no banner, but a soft tone so the
        // reply is noticed.
        Buzz.messageReceived();
        return;
      }

      final contact = await db.contactById(latest.contactId);
      // a muted chat still arrives, it just doesn't announce itself
      if (contact?.muted == true) return;
      final who = contact?.name ?? 'New message';
      final body = switch (latest.kind) {
        'img' => '📷 Photo',
        'voice' => '🎤 Voice message',
        _ => (latest.body ?? '').isEmpty
            ? 'New message'
            : Mask.sensitive(latest.body!),
      };
      Buzz.messageElsewhere();
      await PushService.showMessage(
        title: who,
        body: body.length > 80 ? '${body.substring(0, 80)}…' : body,
        id: latest.contactId.hashCode,
        fromKalId: contact?.kalId,
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
        // deliver anything that was written while offline
        try {
          await _ref.read(messageRepoProvider).flushQueue(me);
        } catch (_) {}
        // drop stale 'typing' flags so the label clears itself
        final typing = _ref.read(typingProvider);
        if (typing.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          for (final e in typing.entries.toList()) {
            if (e.value <= now) {
              _ref.read(typingProvider.notifier).clear(e.key);
            }
          }
        }

        // let pending requests (and the Connect badge) refresh
        _ticks++;
        if (_ticks % 2 == 0) {
          _ref.read(requestsTickProvider.notifier).state++;
          // unlock chats as soon as the other side accepts
          try {
            await _ref.read(contactsRepoProvider).syncState(me);
          } catch (_) {}
        }
        // The status feed carries full photo and video payloads, so pull it
        // sparingly — about once a minute rather than every 15 seconds.
        if (_ticks % 20 == 0) {
          _ref.read(statusRefreshProvider.notifier).state++;
        }
        // keep the on-phone backup current, quietly
        if (_ticks % 200 == 0) {
          try {
            await BackupStore.save(me);
          } catch (_) {}
        }
        // contacts' names/photos change rarely — refresh about every minute
        if (_ticks % 20 == 0) {
          try {
            await _ref.read(contactsRepoProvider).syncProfiles(me);
          } catch (_) {}
        }
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
