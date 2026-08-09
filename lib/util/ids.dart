import 'dart:math';

final _rand = Random.secure();

/// Simple unique id (not RFC-UUID but collision-safe for local use).
String newUuid() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = List.generate(8, (_) => _rand.nextInt(36).toRadixString(36)).join();
  return '$now$r';
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'am' : 'pm';
  return '$h:$m $ap';
}
