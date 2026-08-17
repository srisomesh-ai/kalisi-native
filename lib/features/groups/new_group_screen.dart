import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/feedback.dart';
import '../../data/db/database.dart';
import '../../widgets/avatar.dart';
import '../chats/chat_view.dart';
import '../chats/chats_screen.dart';

/// Pick contacts and start a group.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});
  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _name = TextEditingController();
  final _picked = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create(List<Contact> all) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the group a name')),
      );
      return;
    }
    if (_picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one member')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      final members =
          all.where((c) => _picked.contains(c.id)).toList();
      final group = await ref.read(messageRepoProvider).createGroup(
            me: me,
            name: name,
            members: members,
          );
      Feedback.groupCreated();
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ChatView(contact: group),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the group')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final contacts = ref.watch(contactsStreamProvider);

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('New group',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: contacts.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: KColors.teal)),
        error: (_, __) =>
            Center(child: Text('Could not load contacts',
                style: TextStyle(color: s.muted))),
        data: (all) {
          final people = all.where((c) => !c.isGroup && !c.pending).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  controller: _name,
                  style: TextStyle(color: s.text, fontSize: 16),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Group name',
                    hintStyle: TextStyle(color: s.faint),
                    filled: true,
                    fillColor: s.panel2,
                    prefixIcon: const Icon(Icons.groups_rounded,
                        color: KColors.teal),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Row(
                  children: [
                    Text('MEMBERS',
                        style: TextStyle(
                            color: s.faint,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7)),
                    const Spacer(),
                    Text('${_picked.length} selected',
                        style: TextStyle(color: KColors.teal, fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (people.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                          'Add some friends first — you need contacts to make a group.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: s.muted, fontSize: 14)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (_, i) {
                      final c = people[i];
                      final on = _picked.contains(c.id);
                      return CheckboxListTile(
                        value: on,
                        activeColor: KColors.teal,
                        controlAffinity: ListTileControlAffinity.trailing,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _picked.add(c.id);
                          } else {
                            _picked.remove(c.id);
                          }
                        }),
                        secondary: Avatar(
                          seed: c.kalId,
                          label: c.name.isNotEmpty
                              ? c.name[0].toUpperCase()
                              : '?',
                          size: 44,
                          photo: c.avatar,
                        ),
                        title: Text(c.name,
                            style: TextStyle(
                                color: s.text,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600)),
                        subtitle: c.username != null
                            ? Text('@${c.username}',
                                style:
                                    TextStyle(color: s.muted, fontSize: 13))
                            : null,
                      );
                    },
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _create(people),
                      style: FilledButton.styleFrom(
                        backgroundColor: KColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white))
                          : const Text('Create group',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
