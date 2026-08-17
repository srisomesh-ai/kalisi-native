import 'package:flutter/services.dart';

/// One place for the little sounds and taps the app makes.
///
/// Uses the system's own click and haptics, so nothing is bundled and the
/// phone's silent switch is respected. Everything is fire-and-forget: a
/// failure here should never interrupt what the user was doing.
class Feedback {
  static bool enabled = true;

  // ---- building blocks ----

  static void _tick() {
    if (!enabled) return;
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  static void _light() {
    if (!enabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static void _medium() {
    if (!enabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static void _heavy() {
    if (!enabled) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static void _select() {
    if (!enabled) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Two taps in quick succession, for things worth noticing.
  static Future<void> _double() async {
    if (!enabled) return;
    _tick();
    await Future.delayed(const Duration(milliseconds: 90));
    _light();
  }

  // ---- messages ----

  /// A message leaves the phone.
  static void messageSent() {
    _tick();
    _select();
  }

  /// A message arrives while that chat is open.
  static void messageReceived() {
    _tick();
    _light();
  }

  /// A message arrives for a chat that isn't on screen — the notification
  /// carries the sound, so only a small tap here.
  static void messageElsewhere() => _light();

  /// Something couldn't be sent.
  static void failed() {
    _heavy();
  }

  // ---- reactions and edits ----

  static void reaction() {
    _tick();
    _medium();
  }

  static void messageDeleted() => _medium();

  static void messageEdited() => _select();

  static void starred() {
    _tick();
    _select();
  }

  // ---- voice ----

  static void recordStart() => _medium();

  static void recordStop() => _light();

  // ---- status ----

  /// Your own update goes out.
  static Future<void> statusPosted() => _double();

  /// Moving between someone's updates.
  static void statusAdvance() => _select();

  static void statusDeleted() => _medium();

  // ---- contacts and groups ----

  static Future<void> requestAccepted() => _double();

  static void requestSent() {
    _tick();
    _light();
  }

  static Future<void> groupCreated() => _double();

  // ---- calls ----

  static void callConnected() => _medium();

  static void callEnded() => _light();

  // ---- general ----

  /// Any ordinary confirmation: a toggle, a picker, a saved setting.
  static void tap() => _select();

  /// A destructive or irreversible action.
  static void warn() => _heavy();
}
