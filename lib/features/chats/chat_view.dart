import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
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

  Future<void> _sendPhoto() async {
    if (_sending) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (file == null) return;
      setState(() => _sending = true);
      final bytes = await file.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(messageRepoProvider).sendMedia(
            me: me,
            contact: widget.contact,
            kind: 'img',
            dataUrl: dataUrl,
            localPath: file.path,
          );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send photo')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickCamera() async {
    if (_sending) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );
      if (file == null) return;
      setState(() => _sending = true);
      final bytes = await file.readAsBytes();
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(messageRepoProvider).sendMedia(
            me: me,
            contact: widget.contact,
            kind: 'img',
            dataUrl: dataUrl,
            localPath: file.path,
          );
      _scrollToBottom();
    } catch (_) {
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
            onPhoto: _sendPhoto,
            onCamera: _pickCamera,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  final Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final mine = message.fromMe == 'me';
    final bg = mine ? s.mine : s.theirs;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final reaction = message.reactionTheirs ?? message.reactionMine;

    return Container(
      alignment: align,
      margin: EdgeInsets.only(
          top: 3, bottom: reaction != null ? 16 : 3),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPress: () => _showReactionPicker(context, ref),
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
                      _content(context, s),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(fmtTime(message.ts),
                              style: TextStyle(color: s.faint, fontSize: 10.5)),
                          if (mine) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.status == 'delivered' ||
                                      message.status == 'read'
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
              ),
              // Floating reaction chip (outside the bubble, like the web)
              if (reaction != null)
                Positioned(
                  bottom: -14,
                  right: mine ? 8 : null,
                  left: mine ? null : 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: s.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: s.bg, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Text(reaction, style: const TextStyle(fontSize: 14)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showReactionPicker(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    const emojis = ['❤️', '😂', '👍', '🔥', '😮', '🙏'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: s.panel,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: emojis
              .map((e) => GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref.read(messageRepoProvider).reactTo(
                            ref.read(activePersonaProvider).valueOrNull!,
                            message,
                            e,
                          );
                    },
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, KScheme s) {
    switch (message.kind) {
      case 'img':
        return _ImageContent(dataUrl: message.body);
      case 'voice':
        return _VoiceContent(message: message);
      default:
        return Text(message.body ?? '',
            style: TextStyle(color: s.text, fontSize: 15.5, height: 1.3));
    }
  }
}

/// Renders a base64 data-URL image inside a bubble, tappable to view fullscreen.
class _ImageContent extends StatelessWidget {
  final String? dataUrl;
  const _ImageContent({this.dataUrl});
  @override
  Widget build(BuildContext context) {
    final bytes = _decode(dataUrl);
    if (bytes == null) {
      return const Text('📷 Photo');
    }
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FullscreenImage(bytes: bytes),
          fullscreenDialog: true,
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 300),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Uint8List? _decode(String? url) {
    if (url == null) return null;
    try {
      final i = url.indexOf(',');
      final b64 = i >= 0 ? url.substring(i + 1) : url;
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }
}

/// Fullscreen image viewer with pinch-to-zoom.
class _FullscreenImage extends StatelessWidget {
  final Uint8List bytes;
  const _FullscreenImage({required this.bytes});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// A simple voice-message player bubble.
class _VoiceContent extends StatefulWidget {
  final Message message;
  const _VoiceContent({required this.message});
  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    final data = widget.message.body;
    if (data == null) return;
    try {
      final i = data.indexOf(',');
      final b64 = i >= 0 ? data.substring(i + 1) : data;
      final bytes = base64Decode(b64);
      await _player.play(BytesSource(bytes));
      setState(() => _playing = true);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [KColors.gold, KColors.ember]),
              shape: BoxShape.circle,
            ),
            child: Icon(_playing ? Icons.stop : Icons.play_arrow,
                color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.graphic_eq, color: s.muted, size: 22),
        const SizedBox(width: 8),
        Text('Voice', style: TextStyle(color: s.muted, fontSize: 13)),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onPhoto,
    required this.onCamera,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  void _showAttach(BuildContext context) {
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
              leading: const Icon(Icons.photo_library_rounded,
                  color: KColors.gold),
              title: Text('Photo library', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                widget.onPhoto();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: KColors.gold),
              title: Text('Camera', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                widget.onCamera();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
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
            IconButton(
              onPressed: () => _showAttach(context),
              icon: Icon(Icons.add_circle_outline_rounded,
                  color: s.muted, size: 26),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: s.panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: s.line),
                ),
                child: TextField(
                  controller: widget.controller,
                  style: TextStyle(color: s.text, fontSize: 15.5),
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: s.faint),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => widget.onSend(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.sending ? null : widget.onSend,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [KColors.gold, KColors.ember]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: KColors.ember.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: widget.sending
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
