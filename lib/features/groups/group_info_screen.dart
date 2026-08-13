import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../widgets/avatar.dart';

/// Group info — members, rename, add/remove, leave.
/// Shown instead of the contact screen when the chat is a group.
class GroupInfoScreen extends ConsumerStatefulWidget {
  final Contact group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  List<String> _members = const [];
  String? _owner;
  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _name = widget.group.name;
    _load();
  }

  bool get _isOwner {
    final me = ref.read(activePersonaProvider).valueOrNull;
    return me != null && _owner == me.kalId;
  }

  Future<void> _load() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    try {
      final res = await ref.read(apiProvider).groupInfo(
            kalId: me.kalId,
            token: me.token,
            gid: widget.group.kalId,
          );
      final g = res['group'] as Map?;
      if (g != null && mounted) {
        setState(() {
          _members =
              ((g['members'] as List?) ?? const []).map((e) => '$e').toList();
          _owner = g['owner']?.toString();
          _name = g['name']?.toString() ?? widget.group.name;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    // fall back to what we stored locally
    if (mounted) {
      setState(() {
        try {
          _members = ((jsonDecode(widget.group.groupMembers ?? '[]') as List))
              .map((e) => '$e')
              .toList();
        } catch (_) {}
        _loading = false;
      });
    }
  }

  Future<void> _act(
    String act, {
    List<String>? members,
    String? member,
    String? name,
  }) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    try {
      final res = await ref.read(apiProvider).groupUpdate(
            kalId: me.kalId,
            token: me.token,
            gid: widget.group.kalId,
            act: act,
            members: members,
            member: member,
            name: name,
          );
      if (res['members'] != null && mounted) {
        setState(() => _members =
            (res['members'] as List).map((e) => '$e').toList());
        await ref.read(dbProvider).setGroupMembers(
            widget.group.id, jsonEncode(_members));
      }
      if (act == 'rename' && name != null) {
        await ref.read(dbProvider).setContactProfile(widget.group.id,
            name: name, avatar: widget.group.avatar ?? '');
        if (mounted) setState(() => _name = name);
      }
      if (act == 'leave' && mounted) {
        await ref.read(dbProvider).deleteContact(widget.group.id);
        if (mounted) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You left $_name')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That didn't work")),
        );
      }
    }
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _name);
    final s = KScheme.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.panel,
        title: Text('Group name', style: TextStyle(color: s.text)),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          style: TextStyle(color: s.text),
          decoration: InputDecoration(
            filled: true,
            fillColor: s.panel2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: s.muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: KColors.teal),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _act('rename', name: name);
  }

  Future<void> _addMembers() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    final all = await ref.read(dbProvider).contactsFor(me.id);
    final candidates = all
        .where((c) => !c.isGroup && !c.pending && !_members.contains(c.kalId))
        .toList();
    if (!mounted) return;

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Everyone you know is already in')),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Row(
                  children: [
                    Text('Add to $_name',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${picked.length} selected',
                        style: const TextStyle(
                            color: KColors.teal,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final c = candidates[i];
                    final on = picked.contains(c.kalId);
                    return CheckboxListTile(
                      value: on,
                      activeColor: KColors.teal,
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (v) => setSheet(() {
                        v == true
                            ? picked.add(c.kalId)
                            : picked.remove(c.kalId);
                      }),
                      secondary: Avatar(
                        seed: c.kalId,
                        label:
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        size: 42,
                        photo: c.avatar,
                      ),
                      title: Text(c.name, style: TextStyle(color: s.text)),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: picked.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: KColors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Add',
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

    if (go == true && picked.isNotEmpty) {
      await _act('add', members: picked.toList());
      // hand the group key to the new members
      await _shareKeyWith(picked.toList());
    }
  }

  /// New members need the group's shared key to read anything.
  Future<void> _shareKeyWith(List<String> kalIds) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final key = widget.group.groupKey;
    if (me == null || key == null) return;
    final db = ref.read(dbProvider);
    for (final id in kalIds) {
      final c = await db.contactByKalId(me.id, id);
      if (c == null) continue;
      try {
        await ref.read(messageRepoProvider).shareGroupKey(
              me: me,
              to: c,
              gid: widget.group.kalId,
              name: _name,
              key: key,
              members: _members,
            );
      } catch (_) {}
    }
  }

  Future<void> _confirmLeave() async {
    final s = KScheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.panel,
        title: Text('Leave $_name?', style: TextStyle(color: s.text)),
        content: Text(
            'You will stop receiving messages from this group and it will be removed from this phone.',
            style: TextStyle(color: s.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: s.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(
                    color: KColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) await _act('leave');
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: KColors.teal,
            foregroundColor: Colors.white,
            actions: [
              if (_isOwner)
                IconButton(
                  tooltip: 'Rename',
                  onPressed: _rename,
                  icon: const Icon(Icons.edit_rounded),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(_name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [KColors.teal, KColors.teal2],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Container(
                      width: 108,
                      height: 108,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white24, width: 3),
                      ),
                      child: const Icon(Icons.groups_rounded,
                          color: Colors.white, size: 52),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: KColors.tealSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                      '${_members.length} member${_members.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: KColors.teal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 18),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Text('MEMBERS',
                        style: TextStyle(
                            color: s.faint,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7)),
                    const Spacer(),
                    if (_isOwner)
                      TextButton.icon(
                        onPressed: _addMembers,
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 17),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                            foregroundColor: KColors.teal),
                      ),
                  ],
                ),
              ),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: KColors.teal)),
                )
              else
                ..._members.map((kid) => _MemberRow(
                      kalId: kid,
                      isOwner: kid == _owner,
                      isMe: me != null && kid == me.kalId,
                      canRemove: _isOwner && kid != _owner,
                      onRemove: () => _act('remove', member: kid),
                    )),

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    'Group messages are encrypted with a key shared by everyone in the group.',
                    style: TextStyle(
                        color: s.faint, fontSize: 12.5, height: 1.45)),
              ),

              const SizedBox(height: 22),
              ListTile(
                leading: const Icon(Icons.badge_outlined, color: KColors.teal),
                title: Text('Group ID',
                    style: TextStyle(color: s.muted, fontSize: 12.5)),
                subtitle: Text(widget.group.kalId,
                    style: TextStyle(
                        color: s.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: widget.group.kalId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Copied'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  icon: Icon(Icons.copy_rounded, size: 18, color: s.faint),
                ),
              ),

              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.logout_rounded,
                    color: KColors.danger),
                title: const Text('Leave group',
                    style: TextStyle(
                        color: KColors.danger,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600)),
                onTap: _confirmLeave,
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String kalId;
  final bool isOwner;
  final bool isMe;
  final bool canRemove;
  final VoidCallback onRemove;
  const _MemberRow({
    required this.kalId,
    required this.isOwner,
    required this.isMe,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;

    return FutureBuilder<Contact?>(
      future: me == null
          ? Future.value(null)
          : ref.read(dbProvider).contactByKalId(me.id, kalId),
      builder: (_, snap) {
        final c = snap.data;
        final name = isMe ? 'You' : (c?.name ?? kalId);
        return ListTile(
          leading: Avatar(
            seed: kalId,
            label: name.isNotEmpty ? name[0].toUpperCase() : '?',
            size: 44,
            photo: c?.avatar,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: s.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600)),
              ),
              if (isOwner) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: KColors.amberBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Text('Admin',
                      style: TextStyle(
                          color: KColors.amberInk,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          subtitle: c?.username != null
              ? Text('@${c!.username}',
                  style: TextStyle(color: s.muted, fontSize: 12.5))
              : Text(kalId,
                  style: TextStyle(color: s.faint, fontSize: 11.5)),
          trailing: canRemove
              ? IconButton(
                  tooltip: 'Remove',
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      color: KColors.danger, size: 21),
                )
              : null,
        );
      },
    );
  }
}
