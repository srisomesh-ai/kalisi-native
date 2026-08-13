import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../widgets/avatar.dart';

/// Pick one or more chats and forward a message to them.
class ForwardSheet {
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    Message message,
  ) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;

    final all = await ref.read(dbProvider).contactsFor(me.id);
    final targets = all
        .where((c) => !c.pending && !c.blocked && c.id != message.contactId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!context.mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other chats to forward to')),
      );
      return;
    }

    final picked = <String>{};
    final s = KScheme.of(context);

    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: s.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.forward_rounded, color: KColors.teal),
                    const SizedBox(width: 10),
                    Text('Forward to',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (picked.isNotEmpty)
                      Text('${picked.length}',
                          style: const TextStyle(
                              color: KColors.teal,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: targets.length,
                  itemBuilder: (_, i) {
                    final c = targets[i];
                    final on = picked.contains(c.id);
                    return CheckboxListTile(
                      value: on,
                      activeColor: KColors.teal,
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (v) => setSheet(() {
                        v == true ? picked.add(c.id) : picked.remove(c.id);
                      }),
                      secondary: c.isGroup
                          ? Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                color: KColors.tealSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.groups_rounded,
                                  color: KColors.teal, size: 22),
                            )
                          : Avatar(
                              seed: c.kalId,
                              label: c.name.isNotEmpty
                                  ? c.name[0].toUpperCase()
                                  : '?',
                              size: 44,
                              photo: c.avatar,
                            ),
                      title: Text(c.name,
                          style: TextStyle(
                              color: s.text, fontWeight: FontWeight.w600)),
                      subtitle: c.isGroup
                          ? Text('Group',
                              style:
                                  TextStyle(color: s.muted, fontSize: 12.5))
                          : (c.username != null
                              ? Text('@${c.username}',
                                  style: TextStyle(
                                      color: s.muted, fontSize: 12.5))
                              : null),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        picked.isEmpty ? null : () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: KColors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Send',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (go != true || picked.isEmpty) return;

    final repo = ref.read(messageRepoProvider);
    final db = ref.read(dbProvider);
    var sent = 0;

    for (final id in picked) {
      final c = await db.contactById(id);
      if (c == null) continue;
      try {
        if (c.isGroup) {
          // groups take text only for now
          final text = switch (message.kind) {
            'img' => '📷 Photo',
            'voice' => '🎤 Voice message',
            _ => message.body ?? '',
          };
          if (text.isEmpty) continue;
          await repo.sendGroupText(me: me, group: c, text: text);
        } else if (message.kind == 'img' || message.kind == 'voice') {
          final data = message.body;
          if (data == null || data.isEmpty) continue;
          await repo.sendMedia(
            me: me,
            contact: c,
            kind: message.kind,
            dataUrl: data,
          );
        } else {
          final text = message.body ?? '';
          if (text.isEmpty) continue;
          await repo.sendText(me: me, contact: c, text: text);
        }
        sent++;
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(sent == 1 ? 'Forwarded' : 'Forwarded to $sent chats')),
      );
    }
  }
}
