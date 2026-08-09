import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';

/// Streams messages for a given contact from the local database.
final messagesProvider =
    StreamProvider.family<List<Message>, String>((ref, contactId) {
  return ref.watch(dbProvider).watchMessages(contactId);
});

class ChatView extends ConsumerStatefulWidget {
  final Contact contact;
  const ChatView({super.key, required this.contact});
  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() => _sending = true);
    try {
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(messageRepoProvider).sendText(
            me: me,
            contact: widget.contact,
            text: text,
          );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send — check connection')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final messages = ref.watch(messagesProvider(widget.contact.id));

    ref.listen(messagesProvider(widget.contact.id), (_, __) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(
              seed: widget.contact.kalId,
              label: widget.contact.name.isNotEmpty
                  ? widget.contact.name[0].toUpperCase()
                  : '?',
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.contact.name,
                      style: TextStyle(
                          color: s.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700)),
                  Text('end-to-end encrypted',
                      style: TextStyle(color: s.faint, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const SizedBox(),
              error: (e, _) => Center(
                  child: Text('Could not load messages',
                      style: TextStyle(color: s.muted))),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        'This is the start of your encrypted chat with ${widget.contact.name}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: s.faint, fontSize: 13.5),
                      ),
                    ),
                  );
                }
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _Bubble(message: list[i]),
                );
              },
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final mine = message.fromMe == 'me';
    final bg = mine ? s.mine : s.theirs;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;

    return Container(
      alignment: align,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.body ?? '',
                style: TextStyle(color: s.text, fontSize: 15.5, height: 1.3)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fmtTime(message.ts),
                    style: TextStyle(color: s.faint, fontSize: 10.5)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == 'delivered' || message.status == 'read'
                        ? Icons.done_all
                        : Icons.done,
                    size: 14,
                    color: message.status == 'read'
                        ? KColors.gold
                        : s.faint,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: s.bg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: s.panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: s.line),
                ),
                child: TextField(
                  controller: controller,
                  style: TextStyle(color: s.text, fontSize: 15.5),
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: s.faint),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [KColors.gold, KColors.ember]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: KColors.ember.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
