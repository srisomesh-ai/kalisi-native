import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';
import 'status_screen.dart';

/// Fullscreen status view: react, reply, and (for your own) see who viewed.
class StatusViewer extends ConsumerStatefulWidget {
  final StatusItem item;
  final bool mine;
  const StatusViewer({super.key, required this.item, this.mine = false});

  @override
  ConsumerState<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends ConsumerState<StatusViewer> {
  final _reply = TextEditingController();
  String? _myReaction;
  int _reactionCount = 0;
  int _viewCount = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _markViewed();
    _loadReactions();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  int? get _sid => int.tryParse(widget.item.id);

  Future<void> _markViewed() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null || widget.mine) return;
    try {
      await ref.read(apiProvider).statusView(
            kalId: me.kalId,
            token: me.token,
            statusId: sid,
          );
    } catch (_) {}
  }

  Future<void> _loadReactions() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    try {
      final res = await ref.read(apiProvider).statusReactions(
            kalId: me.kalId,
            token: me.token,
            statusId: sid,
          );
      if (!mounted) return;
      setState(() {
        _reactionCount = (res['count'] as num?)?.toInt() ?? 0;
        final mine = res['mine'];
        _myReaction = (mine == null || '$mine'.isEmpty) ? null : '$mine';
      });
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    // optimistic
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
            kalId: me.kalId,
            token: me.token,
            statusId: sid,
            emoji: emoji,
          );
    } catch (_) {}
    _loadReactions();
  }

  /// Reply goes to the poster as a normal encrypted chat message.
  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;

    final db = ref.read(dbProvider);
    final contact = await db.contactByKalId(me.id, widget.item.kalId);
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
      final quoted = widget.item.type == 'text'
          ? '↩ "${widget.item.payload.length > 60 ? '${widget.item.payload.substring(0, 60)}…' : widget.item.payload}"\n'
          : '↩ (status)\n';
      await ref.read(messageRepoProvider).sendText(
            me: me,
            contact: contact,
            text: '$quoted$text',
          );
      _reply.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replied to ${widget.item.name}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send reply')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showViewers() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    final sid = _sid;
    if (me == null || sid == null) return;
    List viewers = const [];
    try {
      final res = await ref.read(apiProvider).statusViewers(
            kalId: me.kalId,
            token: me.token,
            statusId: sid,
          );
      viewers = (res['viewers'] as List?) ?? const [];
    } catch (_) {}
    if (!mounted) return;
    final s = KScheme.of(context);
    showModalBottomSheet(
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
                child: Text('No views yet',
                    style: TextStyle(color: s.muted, fontSize: 14)),
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
                        size: 40,
                      ),
                      title: Text(nm, style: TextStyle(color: s.text)),
                      subtitle: v['username'] != null
                          ? Text('@${v['username']}',
                              style: TextStyle(color: s.muted, fontSize: 12.5))
                          : null,
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final photo = item.type == 'photo' ? Avatar.decode(item.payload) : null;
    final pair = KColors.avatarPairFor(item.kalId);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // content
          Positioned.fill(
            child: photo != null
                ? Center(
                    child: InteractiveViewer(
                      child: Image.memory(photo, fit: BoxFit.contain),
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
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Text(
                      item.payload,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                    ),
                  ),
          ),

          // top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                  Avatar(
                    seed: item.kalId,
                    label:
                        item.name.isNotEmpty ? item.name[0].toUpperCase() : '?',
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15.5)),
                        Text(_ago(item.ts),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
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
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: widget.mine
                    ? _OwnerBar(
                        viewCount: _viewCount,
                        reactionCount: _reactionCount,
                        onViewers: _showViewers,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // quick reactions
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: ['❤️', '😂', '👍', '🔥', '😮', '🙏']
                                .map((e) => GestureDetector(
                                      onTap: () => _react(e),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 150),
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 5),
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: _myReaction == e
                                              ? Colors.white24
                                              : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(e,
                                            style: TextStyle(
                                                fontSize:
                                                    _myReaction == e ? 30 : 25)),
                                      ),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          // reply box
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.16),
                                    borderRadius: BorderRadius.circular(26),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18),
                                  child: TextField(
                                    controller: _reply,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 15),
                                    decoration: const InputDecoration(
                                      hintText: 'Reply…',
                                      hintStyle: TextStyle(color: Colors.white70),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding:
                                          EdgeInsets.symmetric(vertical: 13),
                                    ),
                                    onSubmitted: (_) => _sendReply(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _sending ? null : _sendReply,
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: const BoxDecoration(
                                    color: KColors.teal,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _sending
                                      ? const Padding(
                                          padding: EdgeInsets.all(13),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Icon(Icons.send_rounded,
                                          color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(int ts) {
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Bottom bar shown on your own status: views + reactions.
class _OwnerBar extends StatelessWidget {
  final int viewCount;
  final int reactionCount;
  final VoidCallback onViewers;
  const _OwnerBar({
    required this.viewCount,
    required this.reactionCount,
    required this.onViewers,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onViewers,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_outlined,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('See who viewed',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            if (reactionCount > 0) ...[
              const SizedBox(width: 14),
              Text('❤ $reactionCount',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}
