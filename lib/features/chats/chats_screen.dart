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

/// Which filter chip is active: 0=All 1=Unread 2=Favourites 3=Groups
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
        // ---- top bar: brand + small icons ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
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
              _TopIcon(
                icon: Icons.qr_code_rounded,
                onTap: () {},
              ),
              _TopIcon(
                icon: Icons.dark_mode_outlined,
                onTap: () {
                  final m = ref.read(themeModeProvider);
                  ref.read(themeModeProvider.notifier).state =
                      m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
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
                          color: s.faint,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
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
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            children: [
              _Chip(
                  label: 'All',
                  on: filter == 0,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = 0),
              _Chip(
                  label: 'Unread',
                  on: filter == 1,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = 1),
              _Chip(
                  label: 'Favourites',
                  on: filter == 2,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = 2),
              _Chip(
                  label: 'Groups',
                  on: filter == 3,
                  onTap: () => ref.read(chatFilterProvider.notifier).state = 3),
            ],
          ),
        ),

        // ---- rows ----
        Expanded(
          child: contacts.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: KColors.teal)),
            error: (_, __) =>
                Center(child: Text('Could not load chats',
                    style: TextStyle(color: s.muted))),
            data: (list) {
              var shown = list;
              if (query.isNotEmpty) {
                shown = shown
                    .where((c) => c.name.toLowerCase().contains(query))
                    .toList();
              }
              if (shown.isEmpty) return _Empty(hasAny: list.isNotEmpty);
              return ListView.builder(
                padding: const EdgeInsets.only(top: 2, bottom: 90),
                itemCount: shown.length,
                itemBuilder: (_, i) => _ChatRow(contact: shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: s.text, size: 23),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? KColors.tealSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: on ? Colors.transparent : s.line, width: 1.2),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                  color: on ? KColors.teal : s.muted,
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                )),
          ),
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
    bool mineLast = false;
    bool read = false;
    msgs.whenData((list) {
      if (list.isEmpty) return;
      final m = list.last;
      mineLast = m.fromMe == 'me';
      read = m.status == 'read';
      preview = switch (m.kind) {
        'img' => 'Photo',
        'voice' => 'Voice message',
        _ => (m.body ?? '').replaceAll('\n', ' '),
      };
      time = fmtTime(m.ts);
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
                  Text(contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: s.text,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                      )),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (mineLast) ...[
                        Icon(Icons.done_all_rounded,
                            size: 15,
                            color: read ? KColors.teal : s.faint),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: s.muted, fontSize: 14.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time,
                style: TextStyle(
                    color: s.faint, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool hasAny;
  const _Empty({required this.hasAny});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: const BoxDecoration(
                  color: KColors.tealSoft, shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: KColors.teal, size: 32),
            ),
            const SizedBox(height: 16),
            Text(hasAny ? 'No matches' : 'No chats yet',
                style: TextStyle(
                    color: s.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                hasAny
                    ? 'Try a different search.'
                    : 'Go to Connect and add a friend by their @username.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.muted, fontSize: 14.5, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
