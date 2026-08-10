import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';

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
        ts: _ts(m['created_at']),
      );
    }).toList();
  } catch (_) {
    return const [];
  }
});

final statusRefreshProvider = StateProvider<int>((ref) => 0);

int _ts(dynamic v) {
  if (v is int) return v;
  return DateTime.tryParse('$v')?.millisecondsSinceEpoch ?? nowMs();
}

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final feed = ref.watch(statusFeedProvider);
    final me = ref.watch(activePersonaProvider).valueOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Text('Status', style: AppTheme.display(size: 24, color: s.text)),
              const Spacer(),
            ],
          ),
        ),
        // My status composer entry
        InkWell(
          onTap: () => _compose(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Stack(
                  children: [
                    Avatar(
                        seed: me?.username ?? 'me',
                        label: (me?.name.isNotEmpty ?? false)
                            ? me!.name[0].toUpperCase()
                            : 'S',
                        size: 52),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: KColors.gold,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.bg, width: 2),
                        ),
                        child: const Icon(Icons.add,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 13),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My status',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    Text('Tap to share an update',
                        style: TextStyle(color: s.muted, fontSize: 13.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(color: s.line, height: 24),
        Expanded(
          child: feed.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: KColors.gold)),
            error: (_, __) =>
                Center(child: Text('Could not load', style: TextStyle(color: s.muted))),
            data: (items) {
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.blur_circular_outlined,
                            size: 44, color: s.faint),
                        const SizedBox(height: 14),
                        Text('No recent updates',
                            style: TextStyle(
                                color: s.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('Statuses from your contacts appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: s.muted, fontSize: 14)),
                      ],
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 4),
                itemCount: items.length,
                itemBuilder: (_, i) => _StatusRow(item: items[i]),
              );
            },
          ),
        ),
      ],
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share an update',
                style: AppTheme.display(size: 20, color: s.text)),
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
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [KColors.gold, KColors.ember]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
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
                      padding: EdgeInsets.symmetric(vertical: 14),
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
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final StatusItem item;
  const _StatusRow({required this.item});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: KColors.gold, width: 2),
        ),
        child: Avatar(
            seed: item.kalId,
            label: item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
            size: 46),
      ),
      title: Text(item.name,
          style: TextStyle(
              color: s.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
      subtitle: Text(
          item.type == 'text' ? item.payload : '📷 ${item.type}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: s.muted, fontSize: 13.5)),
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: KColors.dPanel,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          color: KColors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const SizedBox(height: 16),
                  Text(item.payload,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
          ),
        );
      },
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
  final int ts;
  StatusItem({
    required this.id,
    required this.kalId,
    required this.name,
    this.username,
    required this.type,
    required this.payload,
    required this.ts,
  });
}
