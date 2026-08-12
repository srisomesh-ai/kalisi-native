import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';
import 'chat_view.dart';
import '../contact/contact_details.dart';
import '../groups/new_group_screen.dart';
import '../../util/mask.dart';

final chatSearchProvider = StateProvider<String>((ref) => '');
final chatFilterProvider = StateProvider<String>((ref) => 'all');

/// Live list of the active persona's contacts.
final contactsStreamProvider = StreamProvider<List<Contact>>((ref) async* {
  final me = await ref.watch(activePersonaProvider.future);
  if (me == null) {
    yield const <Contact>[];
    return;
  }
  yield* ref.watch(dbProvider).watchContacts(me.id);
});

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final contacts = ref.watch(contactsStreamProvider);
    final query = ref.watch(chatSearchProvider).toLowerCase();

    return Container(
      color: s.bg,
      child: Column(
        children: [
          const _TopBar(),
          const _SearchField(),
          const _FilterChips(),
          Expanded(
            child: contacts.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: KColors.teal)),
              error: (_, __) => Center(
                  child: Text('Could not load chats',
                      style: TextStyle(color: s.muted))),
              data: (list) {
                final filtered = query.isEmpty
                    ? list
                    : list
                        .where((c) => c.name.toLowerCase().contains(query))
                        .toList();
                if (filtered.isEmpty) return const _Empty();
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 20),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _ChatRow(contact: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          const Text(
            'Kalisi',
            style: TextStyle(
              color: KColors.teal,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'New group',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const NewGroupScreen(),
            )),
            icon: Icon(Icons.group_add_outlined, color: s.text, size: 23),
          ),
          IconButton(
            tooltip: 'Menu',
            onPressed: () => _menu(context, ref),
            icon: Icon(Icons.more_vert_rounded, color: s.text, size: 23),
          ),
        ],
      ),
    );
  }
}

/// Overflow menu — real actions, not a hidden theme switch.
void _menu(BuildContext context, WidgetRef ref) {
  final s = KScheme.of(context);
  showModalBottomSheet(
    context: context,
    backgroundColor: s.panel,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.group_add_outlined, color: KColors.teal),
            title: Text('New group', style: TextStyle(color: s.text)),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NewGroupScreen(),
              ));
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.person_add_alt_1_outlined, color: KColors.teal),
            title: Text('Add a friend', style: TextStyle(color: s.text)),
            onTap: () {
              Navigator.pop(ctx);
              ref.read(goToTabProvider.notifier).state = 2;
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: KColors.teal),
            title: Text('Settings', style: TextStyle(color: s.text)),
            onTap: () {
              Navigator.pop(ctx);
              ref.read(goToTabProvider.notifier).state = 3;
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _SearchField extends ConsumerWidget {
  const _SearchField();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    return Padding(
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
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(chatFilterProvider);
    const items = [
      ['all', 'All'],
      ['unread', 'Unread'],
      ['favourites', 'Favourites'],
      ['groups', 'Groups'],
    ];
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        children: [
          for (final it in items) ...[
            _Chip(
              label: it[1],
              on: active == it[0],
              onTap: () => ref.read(chatFilterProvider.notifier).state = it[0],
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: on ? KColors.tealSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? Colors.transparent : const Color(0xFFDCE4E3)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: on ? KColors.teal : s.muted,
            fontSize: 13.5,
            fontWeight: on ? FontWeight.w700 : FontWeight.w600,
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
      if (list.isNotEmpty) {
        final m = list.last;
        mineLast = m.fromMe == 'me';
        read = m.status == 'read';
        preview = switch (m.kind) {
          'img' => '📷 Photo',
          'voice' => '🎤 Voice message',
          _ => Mask.sensitive((m.body ?? '').replaceAll('\n', ' ')),
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
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ContactDetailsScreen(contact: contact),
              )),
              child: Avatar(
                seed: contact.kalId,
                label: contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : '?',
                size: 55,
                photo: contact.avatar,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
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
                      if (mineLast)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(
                            Icons.done_all_rounded,
                            size: 15,
                            color: read ? KColors.teal : s.faint,
                          ),
                        ),
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
            Text(
              time,
              style: TextStyle(
                  color: s.faint, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: KColors.tealSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: KColors.teal, size: 34),
            ),
            const SizedBox(height: 18),
            Text('No chats yet',
                style: TextStyle(
                    color: s.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(
              'Go to Connect and add a friend by their @username to start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.muted, fontSize: 14, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
