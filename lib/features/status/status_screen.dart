import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';

/// One status update from a contact (or me).
class StatusItem {
  final String id;
  final String kalId;
  final String name;
  final String? username;
  final String type;   // text | photo
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
}

final statusRefreshProvider = StateProvider<int>((ref) => 0);

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
        ts: _ts(m['created_at']),
        views: int.tryParse('${m['views'] ?? 0}') ?? 0,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
});

int _ts(dynamic v) {
  if (v is int) return v;
  return DateTime.tryParse('$v')?.millisecondsSinceEpoch ?? nowMs();
}

String _ago(int ts) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts));
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

    return Container(
      color: s.bg,
      child: Column(
        children: [
          // top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                const Text('Status',
                    style: TextStyle(
                        color: KColors.teal,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6)),
                const Spacer(),
                IconButton(
                  onPressed: () => _compose(context, ref),
                  icon: Icon(Icons.photo_camera_outlined,
                      color: s.text, size: 23),
                ),
              ],
            ),
          ),
          // section head
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
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
                  data: (l) => Text(
                      l.isEmpty ? '' : '${l.length} update${l.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: s.faint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  orElse: () => const SizedBox(),
                ),
              ],
            ),
          ),
          Expanded(
            child: feed.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: KColors.teal)),
              error: (_, __) => Center(
                  child: Text('Could not load status',
                      style: TextStyle(color: s.muted))),
              data: (items) => GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 9 / 14,
                ),
                itemCount: items.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return _MyStatusCard(onTap: () => _compose(context, ref));
                  }
                  return _StatusCard(item: items[i - 1]);
                },
              ),
            ),
          ),
        ],
      ),
    );
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
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share an update',
                style: TextStyle(
                    color: s.text, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Friends can see it for 24 hours.',
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Status shared'),
                              duration: Duration(seconds: 2)),
                        );
                      }
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

/// First tile — add your own status.
class _MyStatusCard extends StatelessWidget {
  final VoidCallback onTap;
  const _MyStatusCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: KColors.teal,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: KColors.teal.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 27),
            ),
            const SizedBox(height: 11),
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

class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.panel2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC6D4D2), width: 2),
      ),
      child: child,
    );
  }
}

/// A friend's status as a tall portrait card.
class _StatusCard extends StatelessWidget {
  final StatusItem item;
  const _StatusCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final g = KColors.avatarPairFor(item.kalId);
    final isPhoto = item.type == 'photo' && item.payload.isNotEmpty;
    Uint8List? bytes;
    if (isPhoto) {
      try {
        final i = item.payload.indexOf(',');
        bytes = base64Decode(i >= 0 ? item.payload.substring(i + 1) : item.payload);
      } catch (_) {}
    }
    final fresh = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(item.ts))
            .inHours <
        6;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StatusViewer(item: item),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // background: photo or gradient
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: g,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            // dark fade so text always reads
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x9E000000), Color(0x1F000000), Color(0x1A000000)],
                  stops: [0.0, 0.45, 1.0],
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
                  color: item.seen ? Colors.white.withOpacity(0.45) : null,
                  gradient: item.seen
                      ? null
                      : const LinearGradient(
                          colors: [KColors.amber, Colors.white]),
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: KColors.teal,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.9), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            // NEW tag
            if (fresh)
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
            if (!isPhoto)
              Positioned(
                left: 12,
                right: 12,
                top: 56,
                child: Text(
                  item.payload,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    shadows: [
                      Shadow(color: Color(0x66000000), blurRadius: 6),
                    ],
                  ),
                ),
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
                  Row(
                    children: [
                      Text(_ago(item.ts),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500)),
                      if (item.views > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.visibility_outlined,
                            size: 12, color: Colors.white.withOpacity(0.85)),
                        const SizedBox(width: 3),
                        Text('${item.views}',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Uint8List? bytes) {
    final g = KColors.avatarPairFor(item.kalId);
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(item.name, style: const TextStyle(fontSize: 16)),
        ),
        body: Center(
          child: bytes != null
              ? InteractiveViewer(child: Image.memory(bytes))
              : Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: g,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    item.payload,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        height: 1.4),
                  ),
                ),
        ),
      ),
    ));
  }
}
