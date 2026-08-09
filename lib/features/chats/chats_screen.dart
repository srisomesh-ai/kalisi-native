import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';

/// Streams the active persona's contacts and shows them as a chat list.
final contactsStreamProvider = StreamProvider<List<Contact>>((ref) async* {
  final persona = await ref.watch(activePersonaProvider.future);
  if (persona == null) {
    yield const [];
    return;
  }
  yield* ref.watch(dbProvider).watchContacts(persona.id);
});

class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final contacts = ref.watch(contactsStreamProvider);
    final persona = ref.watch(activePersonaProvider).valueOrNull;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Avatar(
                seed: persona?.username ?? 'me',
                label: (persona?.name.isNotEmpty ?? false)
                    ? persona!.name[0].toUpperCase()
                    : 'S',
                size: 44,
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Kali',
                      style: AppTheme.display(size: 20, color: s.text)),
                  TextSpan(
                      text: 'si',
                      style: AppTheme.display(size: 20, color: KColors.gold)),
                ]),
              ),
              const Spacer(),
              _HeaderIcon(icon: Icons.group_outlined, onTap: () {}),
              _HeaderIcon(icon: Icons.qr_code_rounded, onTap: () {}),
              _HeaderIcon(
                icon: Icons.wb_sunny_outlined,
                onTap: () {
                  final m = ref.read(themeModeProvider);
                  ref.read(themeModeProvider.notifier).state =
                      m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
            ],
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: s.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: s.line),
            ),
            child: TextField(
              style: TextStyle(color: s.text),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: s.faint, size: 20),
                hintText: 'Search chats',
                hintStyle: TextStyle(color: s.faint),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        // List
        Expanded(
          child: contacts.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: KColors.gold)),
            error: (e, _) => Center(
                child: Text('Could not load chats',
                    style: TextStyle(color: s.muted))),
            data: (list) {
              if (list.isEmpty) {
                return _EmptyChats();
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _ChatRow(contact: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: s.muted, size: 22),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  final Contact contact;
  const _ChatRow({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    return InkWell(
      onTap: () {
        // Chat view wired in the next screen.
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Avatar(
                seed: contact.kalId,
                label: contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : '?',
                size: 52),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name,
                      style: TextStyle(
                          color: s.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text('Tap to chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: s.muted, fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: s.faint),
            const SizedBox(height: 16),
            Text('No chats yet',
                style: TextStyle(
                    color: s.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Go to Connect to add a friend by @username or QR code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.muted, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
