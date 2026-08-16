import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';

/// One status update.
class StatusItem {
  final String id;
  final String kalId;
  final String name;
  final String? username;
  final String type; // text | photo | voice
  final String payload;
  final int ts;
  final int views;
  final bool seen;

  StatusItem({
    required this.id,
    required this.kalId,
    required this.name,
    this.username,
    required this.type,
    required this.payload,
    required this.ts,
    this.views = 0,
    this.seen = false,
  });

  bool get isPhoto => type == 'photo';
  bool get isVoice => type == 'voice';
  bool get isVideo => type == 'video';
  bool get isText => type == 'text';

  /// Large media is stored on the server; the payload is then 'file:<url>'.
  bool get isRemote => payload.startsWith('file:');
  String? get remoteUrl => isRemote ? payload.substring(5) : null;

  /// A photo with a track behind it is packed as 'mix:<base64 json>'.
  bool get hasMusic => payload.startsWith('mix:');

  Map<String, String>? get mixed {
    if (!hasMusic) return null;
    try {
      final j = jsonDecode(utf8.decode(base64Decode(payload.substring(4))));
      return {
        'img': '${(j as Map)['img']}',
        'audio': '${j['audio']}',
      };
    } catch (_) {
      return null;
    }
  }

  /// The image to draw, whichever form the status took.
  String get imagePayload => hasMusic ? (mixed?['img'] ?? '') : payload;

  /// Small badge shown on the card so you know the type before opening.
  String? get kindBadge => switch (type) {
        'photo' => '📷',
        'voice' => '🎤',
        'video' => '▶',
        _ => null,
      };

  String get ago {
    var d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (d.isNegative) d = Duration.zero; // clock skew guard
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  /// A status lives 24 hours.
  String get timeLeft {
    final gone = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts));
    final left = const Duration(hours: 24) - gone;
    if (left.isNegative) return 'expired';
    if (left.inHours >= 1) return '${left.inHours} h left';
    return '${left.inMinutes} min left';
  }

  static StatusItem fromMap(Map m) => StatusItem(
        id: m['id'].toString(),
        kalId: m['kal_id'].toString(),
        name: m['name']?.toString() ??
            m['username']?.toString() ??
            'Unknown',
        username: m['username']?.toString(),
        type: m['type']?.toString() ?? 'text',
        payload: m['payload']?.toString() ?? '',
        ts: _ts(m['created_at']),
        views: int.tryParse('${m['views'] ?? 0}') ?? 0,
        seen: m['seen'] == true || m['seen'] == 1,
      );

  static int _ts(dynamic v) {
    if (v is int) return v;
    final raw = '$v'.trim();
    if (raw.isEmpty) return nowMs();
    // MySQL NOW() has no timezone; the server stores UTC, so parsing it as
    // local time made every status look like it was posted "just now".
    final normalised =
        raw.endsWith('Z') || raw.contains('+') ? raw : '${raw.replaceAll(' ', 'T')}Z';
    final parsed = DateTime.tryParse(normalised);
    if (parsed == null) return nowMs();
    return parsed.millisecondsSinceEpoch;
  }
}

/// Everything the status screen needs, already split into mine vs others.
class StatusFeed {
  final List<StatusItem> mine;
  final List<StatusItem> others;
  const StatusFeed({required this.mine, required this.others});

  int get myViews =>
      mine.fold(0, (sum, s) => sum + s.views);
  bool get hasMine => mine.isNotEmpty;
  int get unseenCount => others.where((s) => !s.seen).length;

  /// Others grouped by person, newest first, so the viewer can page through
  /// one person's updates like stories.
  Map<String, List<StatusItem>> get byPerson {
    final map = <String, List<StatusItem>>{};
    for (final s in others) {
      map.putIfAbsent(s.kalId, () => []).add(s);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.ts.compareTo(b.ts));
    }
    return map;
  }
}

final statusRefreshProvider = StateProvider<int>((ref) => 0);

/// Pulls the feed and separates my own updates from my contacts'.
final statusFeedProvider = FutureProvider<StatusFeed>((ref) async {
  ref.watch(statusRefreshProvider);
  final me = await ref.watch(activePersonaProvider.future);
  if (me == null) return const StatusFeed(mine: [], others: []);

  final db = ref.watch(dbProvider);
  final contacts = await db.contactsFor(me.id);
  final ids = contacts
      .where((c) => !c.isGroup)
      .map((c) => c.kalId)
      .toList()
    ..add(me.kalId); // include myself so my own updates come back

  if (ids.isEmpty) return const StatusFeed(mine: [], others: []);

  try {
    final res = await ref.watch(apiProvider).statusFeed(
          kalId: me.kalId,
          token: me.token,
          contacts: ids,
        );
    final rows = (res['status'] as List?) ?? const [];
    final all = rows.map((r) => StatusItem.fromMap(r as Map)).toList()
      ..sort((a, b) => b.ts.compareTo(a.ts));

    return StatusFeed(
      mine: all.where((s) => s.kalId == me.kalId).toList(),
      others: all.where((s) => s.kalId != me.kalId).toList(),
    );
  } catch (_) {
    return const StatusFeed(mine: [], others: []);
  }
});
