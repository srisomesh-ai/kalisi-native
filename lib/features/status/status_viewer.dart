import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../widgets/avatar.dart';
import 'status_model.dart';

/// Fullscreen status viewer — pages through one person's updates like stories.
class StatusViewer extends ConsumerStatefulWidget {
  final List<StatusItem> items;
  final bool mine;
  const StatusViewer({super.key, required this.items, this.mine = false});

  @override
  ConsumerState<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends ConsumerState<StatusViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  final _reply = TextEditingController();
  final _player = AudioPlayer();

  int _i = 0;
  bool _paused = false;
  bool _sending = false;
  String? _myReaction;
  int _reactionCount = 0;

  static const _perStatus = Duration(seconds: 6);

  StatusItem get item => widget.items[_i];

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _perStatus)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    _open();
  }

  @override
  void dispose() {
    _progress.dispose();
    _reply.dispose();
    _player.dispose();
    super.dispose();
  }

  void _open() {
    _progress
      ..reset()
      ..forward();
    _markViewed();
    _loadReactions();
    if (item.isVoice) _playVoice();
  }

  void _next() {
    if (_i < widget.items.length - 1) {
      setState(() => _i++);
      _player.stop();
      _open();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _player.stop();
      _open();
    }
  }

  void _hold(bool down) {
    setState(() => _paused = down);
    if (down) {
      _progress.stop();
    } else {
      _progress.forward();
    }
  }

  int? get _sid => int.tryParse(item.id);

  Future<void> _markViewed() async {
    if (widget.mine) return;
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    try {
      await ref
          .read(apiProvider)
          .statusView(kalId: me.kalId, token: me.token, statusId: sid);
    } catch (_) {}
  }

  Future<void> _loadReactions() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    try {
      final res = await ref
          .read(apiProvider)
          .statusReactions(kalId: me.kalId, token: me.token, statusId: sid);
      if (!mounted) return;
      setState(() {
        _reactionCount = (res['count'] as num?)?.toInt() ?? 0;
        final mineR = res['mine'];
        _myReaction =
            (mineR == null || '$mineR'.isEmpty) ? null : '$mineR';
      });
    } catch (_) {}
  }

  Future<void> _playVoice() async {
    try {
      final bytes = Avatar.decode(item.payload);
      if (bytes == null) return;
      final p = '${Directory.systemTemp.path}/kstatus_${item.id}.m4a';
      final f = File(p);
      if (!f.existsSync()) await f.writeAsBytes(bytes, flush: true);
      await _player.play(DeviceFileSource(p));
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    setState(() {
      if (_myReaction == emoji) {
        _myReaction = null;
        _reactionCount = (_reactionCount - 1).clamp(0, 1 << 30);
      } else {
        if (_myReaction == null) _reactionCount++;
        _myReaction = emoji;
      }
    });
    try {
      await ref.read(apiProvider).statusReact(
          kalId: me.kalId, token: me.token, statusId: sid, emoji: emoji);
    } catch (_) {}
  }

  /// Floating reaction picker over the status.
  Future<void> _openReactions() async {
    _hold(true);
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (ctx) => _StatusReactionPicker(current: _myReaction),
    );
    _hold(false);
    if (picked != null) await _react(picked);
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    final contact = await ref.read(dbProvider).contactByKalId(me.id, item.kalId);
    if (contact == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add them as a contact to reply')),
        );
      }
      return;
    }
    setState(() => _sending = true);
    try {
      final quote = item.isText
          ? '↩ "${item.payload.length > 60 ? '${item.payload.substring(0, 60)}…' : item.payload}"\n'
          : '↩ (${item.type} status)\n';
      await ref
          .read(messageRepoProvider)
          .sendText(me: me, contact: contact, text: '$quote$text');
      _reply.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replied to ${item.name}')),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Forward this status to a contact as a chat message.
  Future<void> _forward() async {
    _hold(true);
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    final contacts = await ref.read(dbProvider).contactsFor(me.id);
    final people = contacts.where((c) => !c.isGroup && !c.pending).toList();
    if (!mounted) return;

    final s = KScheme.of(context);
    final chosen = await showModalBottomSheet<Contact>(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.forward_rounded, color: KColors.teal),
                  const SizedBox(width: 8),
                  Text('Send status to…',
                      style: TextStyle(
                          color: s.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (people.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No contacts yet',
                    style: TextStyle(color: s.muted)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: people.length,
                  itemBuilder: (_, i) {
                    final c = people[i];
                    return ListTile(
                      leading: Avatar(
                        seed: c.kalId,
                        label: c.name.isNotEmpty
                            ? c.name[0].toUpperCase()
                            : '?',
                        size: 42,
                        photo: c.avatar,
                      ),
                      title: Text(c.name, style: TextStyle(color: s.text)),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (chosen == null) {
      _hold(false);
      return;
    }
    try {
      final repo = ref.read(messageRepoProvider);
      if (item.isPhoto) {
        await repo.sendMedia(
          me: me,
          contact: chosen,
          kind: 'img',
          dataUrl: item.payload,
        );
      } else if (item.isVoice) {
        await repo.sendMedia(
          me: me,
          contact: chosen,
          kind: 'voice',
          dataUrl: item.payload,
        );
      } else {
        await repo.sendText(
          me: me,
          contact: chosen,
          text: '↩ ${item.name}\'s status:\n${item.payload}',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent to ${chosen.name}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that')),
        );
      }
    } finally {
      _hold(false);
    }
  }

  /// Delete one of my own statuses.
  Future<void> _deleteStatus() async {
    _hold(true);
    final s = KScheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.panel,
        title: Text('Delete this update?', style: TextStyle(color: s.text)),
        content: Text(
            'It disappears for everyone straight away, including anyone who has not seen it yet.',
            style: TextStyle(color: s.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: s.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: KColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) {
      _hold(false);
      return;
    }

    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    try {
      await ref.read(apiProvider).statusDelete(
            kalId: me.kalId,
            token: me.token,
            statusId: sid,
          );
      ref.read(statusRefreshProvider.notifier).state++;
      if (mounted) {
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update deleted')),
        );
      }
    } catch (_) {
      _hold(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete that')),
        );
      }
    }
  }

  Future<void> _showViewers() async {
    _hold(true);
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    List viewers = const [];
    if (me != null && sid != null) {
      try {
        final res = await ref.read(apiProvider).statusViewers(
            kalId: me.kalId, token: me.token, statusId: sid);
        viewers = (res['viewers'] as List?) ?? const [];
      } catch (_) {}
    }
    if (!mounted) return;
    final s = KScheme.of(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      color: KColors.teal, size: 20),
                  const SizedBox(width: 8),
                  Text('Viewed by ${viewers.length}',
                      style: TextStyle(
                          color: s.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (viewers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child:
                    Text('No views yet', style: TextStyle(color: s.muted)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: viewers.length,
                  itemBuilder: (_, i) {
                    final v = viewers[i] as Map;
                    final nm = v['name']?.toString() ??
                        v['username']?.toString() ??
                        'Unknown';
                    return ListTile(
                      leading: Avatar(
                          seed: v['viewer']?.toString() ?? nm,
                          label: nm.isNotEmpty ? nm[0].toUpperCase() : '?',
                          size: 40),
                      title: Text(nm, style: TextStyle(color: s.text)),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    _hold(false);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = item.isPhoto ? Avatar.decode(item.payload) : null;
    final pair = KColors.avatarPairFor(item.kalId);

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // content
          Positioned.fill(
            child: bytes != null
                ? Container(
                    color: Colors.black,
                    child: Center(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: pair,
                      ),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(34),
                    child: item.isVoice
                        ? const Icon(Icons.graphic_eq_rounded,
                            color: Colors.white, size: 78)
                        : Text(
                            item.payload,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                                height: 1.4),
                          ),
                  ),
          ),

          // tap zones: left = back, right = forward, hold = pause
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _prev,
                    onLongPressStart: (_) => _hold(true),
                    onLongPressEnd: (_) => _hold(false),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _next,
                    onLongPressStart: (_) => _hold(true),
                    onLongPressEnd: (_) => _hold(false),
                  ),
                ),
              ],
            ),
          ),

          // progress bars
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (_, __) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: i < _i
                                ? 1.0
                                : (i == _i ? _progress.value : 0.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // header
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 20, 8, 0),
                child: Row(
                children: [
                  Avatar(
                    seed: item.kalId,
                    label: item.name.isNotEmpty
                        ? item.name[0].toUpperCase()
                        : '?',
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.mine ? 'Your status' : item.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5)),
                        Text(
                            widget.mine
                                ? '${item.ago} · 👁 ${item.views}'
                                : item.ago,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 11.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 24),
                  ),
                ],
              ),
              ),
            ),
          ),

          // bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: widget.mine
                    ? _OwnerBar(
                        views: item.views,
                        reactions: _reactionCount,
                        onViewers: _showViewers,
                        onDelete: _deleteStatus,
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.3)),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 18),
                              child: TextField(
                                controller: _reply,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15),
                                onTap: () => _hold(true),
                                decoration: InputDecoration(
                                  hintText: 'Reply to ${item.name}…',
                                  hintStyle:
                                      const TextStyle(color: Colors.white70),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                ),
                                onSubmitted: (_) => _sendReply(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // reactions
                          _CircleBtn(
                            icon: Icons.emoji_emotions_outlined,
                            badge: _myReaction,
                            onTap: _openReactions,
                          ),
                          const SizedBox(width: 8),
                          _CircleBtn(
                            icon: _sending
                                ? Icons.hourglass_empty_rounded
                                : Icons.send_rounded,
                            onTap: _sending ? null : _sendReply,
                          ),
                          const SizedBox(width: 8),
                          _CircleBtn(
                              icon: Icons.forward_rounded, onTap: _forward),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? badge;
  const _CircleBtn({required this.icon, this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Icon(icon, color: Colors.white, size: 21),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Text(badge!, style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}

class _OwnerBar extends StatelessWidget {
  final int views;
  final int reactions;
  final VoidCallback onViewers;
  final VoidCallback onDelete;
  const _OwnerBar({
    required this.views,
    required this.reactions,
    required this.onViewers,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onViewers,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.28)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.visibility_outlined,
                      color: Colors.white, size: 19),
                  const SizedBox(width: 8),
                  Text('$views viewers',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  if (reactions > 0) ...[
                    const SizedBox(width: 16),
                    Text('❤ $reactions',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onDelete,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: KColors.danger.withOpacity(0.9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 23),
          ),
        ),
      ],
    );
  }
}


/// Small floating reaction bar for statuses, with the same rise animation.
class _StatusReactionPicker extends StatefulWidget {
  final String? current;
  const _StatusReactionPicker({this.current});
  @override
  State<_StatusReactionPicker> createState() => _StatusReactionPickerState();
}

class _StatusReactionPickerState extends State<_StatusReactionPicker>
    with SingleTickerProviderStateMixin {
  static const _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 26),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _emojis.length; i++)
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) {
                    final start = (i * 0.09).clamp(0.0, 0.6);
                    final v = Curves.easeOutBack.transform(
                      ((_c.value - start) / 0.4).clamp(0.0, 1.0),
                    );
                    return Opacity(
                      opacity: v.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - v)),
                        child: Transform.scale(
                            scale: v.clamp(0.01, 1.2), child: child),
                      ),
                    );
                  },
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, _emojis[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 3),
                      decoration: widget.current == _emojis[i]
                          ? const BoxDecoration(
                              color: KColors.tealSoft, shape: BoxShape.circle)
                          : null,
                      child: Text(_emojis[i],
                          style: const TextStyle(fontSize: 30)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
