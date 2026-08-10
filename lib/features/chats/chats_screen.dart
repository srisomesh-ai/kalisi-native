import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';
import 'chat_view.dart';

/// Streams the active persona's contacts and shows them as a chat list.
final contactsStreamProvider = StreamProvider<List<Contact>>((ref) async* {
  final persona = await ref.watch(activePersonaProvider.future);
  if (persona == null) {
    yield const [];
    return;
  }
  yield* ref.watch(dbProvider).watchContacts(persona.id);
});

/// Which filter chip is active.
final chatFilterProvider = StateProvider<int>((ref) => 0);
final chatSearchProvider = StateProvider<String>((ref) => '');

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final contacts = ref.watch(contactsStreamProvider);
    final filter = ref.watch(chatFilterProvider);
    final query = ref.watch(chatSearchProvider).trim().toLowerCase();

    return Column(
      children: [
        // ---- top bar: brand + small tools (WhatsApp layout) ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
          child: Row(
            children: [
              Text('Kalisi',
                  style: TextStyle(
                    color: KColors.teal,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  )),
              const Spacer(),
              _Tool(icon: Icons.qr_code_rounded, onTap: () {}),
              _Tool(
                icon: Icons.light_mode_outlined,
                onTap: () {
                  final m = ref.read(themeModeProvider);
                  ref.read(themeModeProvider.notifier).state =
                      m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              _Tool(icon: Icons.more_vert_rounded, onTap: () {}),
            ],
          ),
        ),

        // ---- search pill ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: s.panel2,
              borderRadius: BorderRadius.circular(26),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: s.faint, size: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: (v) =>
                        ref.read(chatSearchProvider.notifier).state = v,
                    style: TextStyle(color: s.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(
                          color: s.faint, fontSize: 15, fontWeight: FontWeight.w500),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ---- filter chips ----
        contacts.maybeWhen(
          data: (list) => _Chips(
            all: list.length,
            unread: 0,
            groups: 0,
            selected: filter,
            onSelect: (i) => ref.read(chatFilterProvider.notifier).state = i,
          ),
          orElse: () => _Chips(
            all: 0,
            unread: 0,
            groups: 0,
            selected: filter,
            onSelect: (i) => ref.read(chatFilterProvider.notifier).state = i,
          ),
        ),

        // ---- rows ----
        Expanded(
          child: contacts.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: KColors.teal)),
            error: (e, _) => Center(
                child: Text('Could not load chats',
                    style: TextStyle(color: s.muted))),
            data: (list) {
              final filtered = query.isEmpty
                  ? list
                  : list
                      .where((c) => c.name.toLowerCase().contains(query))
                      .toList();
              if (filtered.isEmpty) return _Empty(searching: query.isNotEmpty);
              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 90),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _ChatRow(contact: filtered[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Tool({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: s.text, size: 22),
    );
  }
}

class _Chips extends StatelessWidget {
  final int all;
  final int unread;
  final int groups;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Chips({
    required this.all,
    required this.unread,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('All', null),
      ('Unread', unread > 0 ? '$unread' : null),
      ('Favourites', null),
      ('Groups', groups > 0 ? '$groups' : null),
    ];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _Chip(
          label: items[i].$1,
          count: items[i].$2,
          on: selected == i,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? count;
  final bool on;
  final VoidCallback onTap;
  const _Chip(
      {required this.label, this.count, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? KColors.tealSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? Colors.transparent : s.line, width: 1.2),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                  color: on ? KColors.teal : s.muted,
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                )),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(count!,
                  style: TextStyle(
                      color: on ? KColors.teal : s.faint,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  final Contact contact;
  const _ChatRow({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final msgs = ref.watch(messagesProvider(contact.id));

    String preview = 'Tap to chat';
    String time = '';
    bool mine = false;
    String? status;

    msgs.whenData((list) {
      if (list.isNotEmpty) {
        final m = list.last;
        mine = m.fromMe == 'me';
        status = m.status;
        preview = switch (m.kind) {
          'img' => '📷 Photo',
          'voice' => '🎤 Voice message',
          _ => (m.body ?? ''),
        };
        time = fmtTime(m.ts);
      }
    });

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatView(contact: contact)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Avatar(
              seed: contact.kalId,
              label: contact.name.isNotEmpty
                  ? contact.name[0].toUpperCase()
                  : '?',
              size: 55,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: s.text,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (mine) ...[
                        Icon(
                          status == 'read' || status == 'delivered'
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 15,
                          color: status == 'read' ? KColors.teal : s.faint,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: s.muted, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time,
                    style: TextStyle(
                        color: s.faint,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool searching;
  const _Empty({required this.searching});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off_rounded : Icons.forum_outlined,
                size: 46, color: s.faint),
            const SizedBox(height: 14),
            Text(searching ? 'No chats found' : 'No chats yet',
                style: TextStyle(
                    color: s.text, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a different name.'
                  : 'Go to Connect and add a friend by their @username.',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
