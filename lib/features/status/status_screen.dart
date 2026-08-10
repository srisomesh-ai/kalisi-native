import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';

/// Status feed for the active persona (their contacts' statuses).
final statusFeedProvider = FutureProvider<List<StatusItem>>((ref) async {
  ref.watch(statusRefreshProvider);
  final me = await ref.watch(activePersonaProvider.future);
  if (me == null) return const [];
  final db = ref.watch(dbProvider);
  final contacts = await db.contactsFor(me.id);
  final ids = contacts.map((c) => c.kalId).toList();
  if (ids.isEmpty) return const [];
  try {
    final res = await ref.watch(apiProvider).statusFeed(
          kalId: me.kalId,
          token: me.token,
          contacts: ids,
        );
    final list = (res['status'] as List?) ?? const [];
    return list.map((r) {
      final m = r as Map;
      return StatusItem(
        id: m['id'].toString(),
        kalId: m['kal_id'].toString(),
        name: m['name']?.toString() ?? m['username']?.toString() ?? 'Unknown',
        username: m['username']?.toString(),
        type: m['type']?.toString() ?? 'text',
        payload: m['payload']?.toString() ?? '',
        views: int.tryParse('${m['views'] ?? 0}') ?? 0,
        ts: _ts(m['created_at']),
      );
    }).toList();
  } catch (_) {
    return const [];
  }
});

final statusRefreshProvider = StateProvider<int>((ref) => 0);
/// Ids of statuses this device has opened.
final statusSeenProvider = StateProvider<Set<String>>((ref) => <String>{});

int _ts(dynamic v) {
  if (v is int) return v;
  return DateTime.tryParse('$v')?.millisecondsSinceEpoch ?? nowMs();
}

String _ago(int ts) {
  final d = Duration(milliseconds: nowMs() - ts);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final feed = ref.watch(statusFeedProvider);
    final seen = ref.watch(statusSeenProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(
            children: [
              Text('Status',
                  style: TextStyle(
                    color: KColors.teal,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  )),
              const Spacer(),
              IconButton(
                onPressed: () => ref.read(statusRefreshProvider.notifier).state++,
                icon: Icon(Icons.refresh_rounded, color: s.text, size: 23),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Text('RECENT UPDATES',
                  style: TextStyle(
                      color: s.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
              const Spacer(),
              feed.maybeWhen(
                data: (l) {
                  final n = l.where((e) => !seen.contains(e.id)).length;
                  return Text(n > 0 ? '$n new' : '',
                      style: TextStyle(
                          color: KColors.amberInk,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700));
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        Expanded(
          child: feed.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: KColors.teal)),
            error: (_, __) => Center(
                child: Text('Could not load', style: TextStyle(color: s.muted))),
            data: (items) => GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 9 / 14,
              ),
              itemCount: items.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _MyStatusCard(onTap: () => _compose(context, ref));
                final item = items[i - 1];
                return _StatusCard(
                  item: item,
                  seen: seen.contains(item.id),
                  onTap: () {
                    ref.read(statusSeenProvider.notifier).state = {
                      ...seen,
                      item.id
                    };
                    _view(context, item);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _view(BuildContext context, StatusItem item) {
    final pair = KColors.avatarPairFor(item.kalId);
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(item.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: pair,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(30),
          child: Text(item.payload,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  height: 1.4)),
        ),
      ),
    ));
  }

  void _compose(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final s = KScheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share an update',
                style: TextStyle(
                    color: s.text, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Disappears after 24 hours.',
                style: TextStyle(color: s.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              style: TextStyle(color: s.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: TextStyle(color: s.faint),
                filled: true,
                fillColor: s.panel2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: KColors.teal,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    final me = ref.read(activePersonaProvider).valueOrNull;
                    if (me == null) return;
                    try {
                      await ref.read(apiProvider).statusPost(
                            kalId: me.kalId,
                            token: me.token,
                            type: 'text',
                            payload: text,
                          );
                      ref.read(statusRefreshProvider.notifier).state++;
                    } catch (_) {}
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: Text('Share',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyStatusCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MyStatusCard({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: s.panel2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: s.line, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                  color: KColors.teal, shape: BoxShape.circle),
              child: const Icon(Icons.add, color: Colors.white, size: 27),
            ),
            const SizedBox(height: 10),
            const Text('My status',
                style: TextStyle(
                    color: KColors.teal,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('Share a photo or a thought',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: s.faint, fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final StatusItem item;
  final bool seen;
  final VoidCallback onTap;
  const _StatusCard(
      {required this.item, required this.seen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pair = KColors.avatarPairFor(item.kalId);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: pair,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // bottom fade so text always reads
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x9E000000), Color(0x1F000000)],
                  stops: [0.0, 0.55],
                ),
              ),
            ),
            // avatar ring
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: seen
                      ? null
                      : const LinearGradient(
                          colors: [KColors.amber, Color(0xFFFFD79A)]),
                  color: seen ? const Color(0x73FFFFFF) : null,
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: pair.last,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                      item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            if (!seen)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KColors.amber,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('NEW',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            // text preview
            if (item.type == 'text')
              Positioned(
                left: 12,
                right: 12,
                top: 56,
                child: Text(item.payload,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ),
            // footer
            Positioned(
              left: 12,
              right: 12,
              bottom: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${_ago(item.ts)} · ${item.views} views',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusItem {
  final String id;
  final String kalId;
  final String name;
  final String? username;
  final String type;
  final String payload;
  final int views;
  final int ts;
  StatusItem({
    required this.id,
    required this.kalId,
    required this.name,
    this.username,
    required this.type,
    required this.payload,
    this.views = 0,
    required this.ts,
  });
}
