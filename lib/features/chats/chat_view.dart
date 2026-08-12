import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';
import '../contact/contact_details.dart';
import '../call/call_screen.dart';
import 'reaction_overlay.dart';
import '../../data/call/call_service.dart';

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
  final _recorder = AudioRecorder();
  bool _sending = false;
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTicker;
  int _recSecs = 0;
  Message? _replyTo;      // message being replied to
  int _lastTypingSent = 0;
  String? _previewPath;   // recorded clip waiting to be sent
  int _previewDur = 0;
  final _previewPlayer = AudioPlayer();
  bool _previewPlaying = false;

  @override
  void initState() {
    super.initState();
    // no alerts while this chat is on screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(openChatIdProvider.notifier).state = widget.contact.id;
    });
    _input.addListener(_onTyping);
  }

  /// Signal 'typing' at most once every 4 seconds while text is being entered.
  void _onTyping() {
    if (_input.text.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTypingSent < 4000) return;
    _lastTypingSent = now;
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    ref.read(messageRepoProvider).sendTyping(me, widget.contact);
  }

  @override
  void dispose() {
    // safe to alert again
    Future.microtask(() {
      try {
        ref.read(openChatIdProvider.notifier).state = null;
      } catch (_) {}
    });
    _input.removeListener(_onTyping);
    _input.dispose();
    _scroll.dispose();
    _recTicker?.cancel();
    _recorder.dispose();
    _previewPlayer.dispose();
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
      if (widget.contact.isGroup) {
        await ref.read(messageRepoProvider).sendGroupText(
              me: me,
              group: widget.contact,
              text: text,
            );
        if (mounted) setState(() => _replyTo = null);
        _scrollToBottom();
        return;
      }
      final replying = _replyTo;
      await ref.read(messageRepoProvider).sendText(
            me: me,
            contact: widget.contact,
            text: text,
            replyTo: replying,
            replyToWho: replying == null
                ? null
                : (replying.fromMe == 'me' ? 'You' : widget.contact.name),
          );
      if (mounted) setState(() => _replyTo = null);
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

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission needed')),
          );
        }
        return;
      }
      final p = '${Directory.systemTemp.path}/kalisi_rec_${nowMs()}.m4a';
      // Small, compatible settings: AAC in m4a, mono, modest bitrate.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: p,
      );
      _recStart = DateTime.now();
      _recSecs = 0;
      _recTicker?.cancel();
      _recTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSecs++);
        if (_recSecs >= 120) _stopRecording();   // cap at 2 minutes
      });
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start recording')),
        );
      }
    }
  }

  /// Stop and keep the clip for preview (not sent yet).
  Future<void> _stopRecording() async {
    _recTicker?.cancel();
    try {
      final path = await _recorder.stop();
      final dur = DateTime.now()
          .difference(_recStart ?? DateTime.now())
          .inSeconds;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _previewPath = path;
        _previewDur = dur;
      });
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// Throw the recording away.
  Future<void> _cancelRecording() async {
    _recTicker?.cancel();
    try {
      if (_recording) await _recorder.stop();
    } catch (_) {}
    await _previewPlayer.stop();
    final p = _previewPath;
    if (p != null) {
      try { File(p).deleteSync(); } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _previewPath = null;
        _previewDur = 0;
        _previewPlaying = false;
      });
    }
  }

  Future<void> _togglePreview() async {
    final p = _previewPath;
    if (p == null) return;
    if (_previewPlaying) {
      await _previewPlayer.pause();
      if (mounted) setState(() => _previewPlaying = false);
      return;
    }
    try {
      await _previewPlayer.play(DeviceFileSource(p));
      if (mounted) setState(() => _previewPlaying = true);
      _previewPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _previewPlaying = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play the recording')),
        );
      }
    }
  }

  /// Send the previewed clip.
  Future<void> _sendVoice() async {
    final p = _previewPath;
    if (p == null) return;
    await _previewPlayer.stop();
    setState(() { _sending = true; _previewPlaying = false; });
    try {
      final bytes = await File(p).readAsBytes();
      if (bytes.length > 1200000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording too long to send')),
          );
        }
        return;
      }
      final dataUrl = 'data:audio/mp4;base64,${base64Encode(bytes)}';
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(messageRepoProvider).sendMedia(
            me: me,
            contact: widget.contact,
            kind: 'voice',
            dataUrl: dataUrl,
            localPath: p,
            durationSec: _previewDur,
          );
      if (mounted) setState(() { _previewPath = null; _previewDur = 0; });
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send voice message')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// With the reversed list, "newest" is offset 0.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final messages = ref.watch(messagesProvider(widget.contact.id));

    ref.listen(messagesProvider(widget.contact.id), (_, __) => _scrollToBottom());

    return PopScope(
      // Back first closes a recording / preview, then leaves the chat.
      canPop: !_recording && _previewPath == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelRecording();
      },
      child: Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: s.chatBg,
      appBar: AppBar(
        titleSpacing: 0,
        actions: (widget.contact.isGroup || widget.contact.pending)
            ? null
            : [
                IconButton(
                  tooltip: 'Audio call',
                  onPressed: () async {
                    final me = ref.read(activePersonaProvider).valueOrNull;
                    if (me == null) return;
                    ref.read(pollerProvider).setFast(true);
                    await ref
                        .read(callServiceProvider)
                        .startCall(me, widget.contact);
                    if (context.mounted) {
                      await Navigator.of(context).push(MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const CallScreen(),
                      ));
                      ref.read(pollerProvider).setFast(false);
                    }
                  },
                  icon: Icon(Icons.call_rounded, color: KColors.teal),
                ),
                const SizedBox(width: 4),
              ],
        backgroundColor: s.panel,
        surfaceTintColor: s.panel,
        foregroundColor: s.text,
        elevation: 0,
        shape: Border(bottom: BorderSide(color: s.line)),
        title: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    ContactDetailsScreen(contact: widget.contact),
              )),
              child: Avatar(
                seed: widget.contact.kalId,
                label: widget.contact.name.isNotEmpty
                    ? widget.contact.name[0].toUpperCase()
                    : '?',
                size: 42,
                photo: widget.contact.avatar,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: s.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700)),
                  _PresenceLine(contact: widget.contact),
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
                // Reversed list: index 0 is the newest, so the view always
                // starts at the latest message and stays there.
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _Bubble(
                    message: list[list.length - 1 - i],
                    onReply: (m) => setState(() => _replyTo = m),
                  ),
                );
              },
            ),
          ),
          if (_replyTo != null && !widget.contact.pending)
            _ReplyBar(
              who: _replyTo!.fromMe == 'me' ? 'You' : widget.contact.name,
              text: switch (_replyTo!.kind) {
                'img' => '📷 Photo',
                'voice' => '🎤 Voice message',
                _ => _replyTo!.body ?? '',
              },
              onClose: () => setState(() => _replyTo = null),
            ),
          if (widget.contact.pending)
            _PendingCard(
                handle: widget.contact.username != null
                    ? '@${widget.contact.username}'
                    : widget.contact.name)
          else
            if (_recording)
              _RecordingBar(
                seconds: _recSecs,
                onCancel: _cancelRecording,
                onStop: _stopRecording,
              )
            else if (_previewPath != null)
              _PreviewBar(
                seconds: _previewDur,
                playing: _previewPlaying,
                sending: _sending,
                onPlay: _togglePreview,
                onDelete: _cancelRecording,
                onSend: _sendVoice,
              )
            else
              _Composer(
                controller: _input,
                sending: _sending,
                recording: false,
                onSend: _send,
                onPhoto: _sendPhoto,
                onCamera: _pickCamera,
                onVoice: _toggleRecording,
              ),
        ],
      ),
      ),
    );
  }
}

class _Bubble extends ConsumerStatefulWidget {
  final Message message;
  final void Function(Message)? onReply;
  const _Bubble({required this.message, this.onReply});

  @override
  ConsumerState<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends ConsumerState<_Bubble> {
  final _key = GlobalKey();

  Message get message => widget.message;
  void Function(Message)? get onReply => widget.onReply;

  @override
  Widget build(BuildContext context) {
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
                onLongPress: () => _openOverlay(context),
                child: Container(
                  key: _key,
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
                      if (message.replyToId != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: const Border(
                              left: BorderSide(color: KColors.teal, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(message.replyToWho ?? '',
                                  style: const TextStyle(
                                      color: KColors.teal,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700)),
                              Text(message.replyToText ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: s.muted, fontSize: 12.5)),
                            ],
                          ),
                        ),
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
                              switch (message.status) {
                                'queued' => Icons.schedule_rounded,
                                'failed' => Icons.error_outline_rounded,
                                'delivered' || 'read' => Icons.done_all,
                                _ => Icons.done,
                              },
                              size: 14,
                              color: switch (message.status) {
                                'read' => KColors.teal,
                                'failed' => KColors.danger,
                                _ => s.faint,
                              },
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

  /// Long-press sheet: reactions + Reply, Copy and Delete.
  /// Long-press: floating reaction bar over the message + actions beneath.
  Future<void> _openOverlay(BuildContext context) async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(
        pos.dx, pos.dy, box.size.width, box.size.height);
    final mine = message.fromMe == 'me';

    final result = await ReactionOverlay.show(
      context: context,
      message: message,
      anchor: rect,
      mine: mine,
      current: message.reactionMine,
    );
    if (result == null || !context.mounted) return;

    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;

    switch (result) {
      case 'reply':
        onReply?.call(message);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body ?? ''));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Copied'), duration: Duration(seconds: 1)),
          );
        }
        break;
      case 'delete':
        if (mine) {
          await ref.read(messageRepoProvider).deleteForEveryone(me, message);
        } else {
          await ref.read(dbProvider).deleteMessageById(message.id);
        }
        break;
      default:
        // anything else is an emoji reaction
        await ref.read(messageRepoProvider).reactTo(me, message, result);
    }
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
  bool _loading = false;
  String? _error;
  String? _filePath;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _pos = Duration.zero; });
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _dur = d);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Android cannot reliably play AAC/m4a from raw bytes, so write the
  /// decoded audio to a real file once and play that.
  Future<String?> _ensureFile() async {
    if (_filePath != null && File(_filePath!).existsSync()) return _filePath;
    final data = widget.message.body;
    if (data == null || data.isEmpty) return null;
    try {
      final i = data.indexOf(',');
      final b64 = i >= 0 ? data.substring(i + 1) : data;
      final bytes = base64Decode(b64);
      // pick the extension from the data URL when we can
      var ext = 'm4a';
      if (data.startsWith('data:audio/')) {
        final mime = data.substring(11, i > 0 ? i : data.length).split(';').first;
        if (mime.contains('mp4') || mime.contains('m4a')) ext = 'm4a';
        else if (mime.contains('aac')) ext = 'aac';
        else if (mime.contains('mpeg') || mime.contains('mp3')) ext = 'mp3';
        else if (mime.contains('wav')) ext = 'wav';
        else if (mime.contains('ogg')) ext = 'ogg';
        else if (mime.contains('webm')) ext = 'webm';
      }
      // Keep media in the app's own storage so it plays offline, like WhatsApp.
      final dir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${dir.path}/media');
      if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
      final p = '${mediaDir.path}/kv_${widget.message.id}.$ext';
      final file = File(p);
      if (!file.existsSync()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      _filePath = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final path = await _ensureFile();
      if (path == null) {
        setState(() { _loading = false; _error = 'Audio unavailable'; });
        return;
      }
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() { _playing = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _playing = false; _error = "Can't play"; });
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final total = _dur.inMilliseconds > 0 ? _dur : Duration.zero;
    final progress = total.inMilliseconds > 0
        ? (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 205,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _loading ? null : _toggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: KColors.teal,
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: s.line,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(KColors.teal),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _error ??
                      (total.inMilliseconds > 0
                          ? '${_fmt(_pos)} / ${_fmt(total)}'
                          : 'Voice message'),
                  style: TextStyle(
                      color: _error != null ? KColors.danger : s.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onVoice;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.recording,
    required this.onSend,
    required this.onPhoto,
    required this.onCamera,
    required this.onVoice,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;
  bool _emoji = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    _focus.dispose();
    super.dispose();
  }

  void _onChange() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

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
                  color: KColors.teal),
              title: Text('Photo library', style: TextStyle(color: s.text)),
              onTap: () {
                Navigator.pop(ctx);
                widget.onPhoto();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_rounded, color: KColors.teal),
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
    return PopScope(
      // Back closes the emoji panel before leaving the chat.
      canPop: !_emoji,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _emoji) setState(() => _emoji = false);
      },
      child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // The rounded input pill with icons inside (WhatsApp style)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: s.panel,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // emoji button — toggles the emoji keyboard
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            if (_emoji) {
                              setState(() => _emoji = false);
                              _focus.requestFocus();
                            } else {
                              FocusScope.of(context).unfocus();
                              Future.delayed(
                                  const Duration(milliseconds: 120), () {
                                if (mounted) setState(() => _emoji = true);
                              });
                            }
                          },
                          icon: Icon(
                              _emoji
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.emoji_emotions_outlined,
                              color: s.faint,
                              size: 24),
                        ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focus,
                        style: TextStyle(color: s.text, fontSize: 16),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        onTap: () {
                          if (_emoji) setState(() => _emoji = false);
                        },
                        decoration: InputDecoration(
                          hintText:
                              widget.recording ? 'Recording…' : 'Message',
                          hintStyle: TextStyle(color: s.faint, fontSize: 16),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                        ),
                        onSubmitted: (_) => widget.onSend(),
                      ),
                    ),
                    // attach + camera inside the pill
                    IconButton(
                      onPressed: () => _showAttach(context),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.attach_file_rounded,
                          color: s.muted, size: 22),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        onPressed: widget.onCamera,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.camera_alt_rounded,
                            color: s.muted, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
            // mic when empty, send when typing (WhatsApp behaviour)
            GestureDetector(
              onTap: widget.sending
                  ? null
                  : (_hasText ? widget.onSend : widget.onVoice),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: widget.recording
                          ? const [KColors.danger, Color(0xFFB93B2C)]
                          : const [KColors.teal, KColors.teal2]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (widget.recording
                              ? KColors.danger
                              : KColors.teal)
                          .withOpacity(0.40),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: widget.sending
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Icon(
                        widget.recording
                            ? Icons.stop_rounded
                            : (_hasText
                                ? Icons.send_rounded
                                : Icons.mic_rounded),
                        color: Colors.white,
                        size: 23),
              ),
            ),
              ],
            ),
          ),
          // Emoji keyboard panel
          if (_emoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (cat, emoji) {
                  final c = widget.controller;
                  c.text = c.text + emoji.emoji;
                  c.selection =
                      TextSelection.fromPosition(
                          TextPosition(offset: c.text.length));
                },
                config: Config(
                  height: 280,
                  emojiViewConfig: EmojiViewConfig(
                    backgroundColor: s.panel,
                    columns: 8,
                    emojiSizeMax: 28,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: s.panel,
                    indicatorColor: KColors.teal,
                    iconColorSelected: KColors.teal,
                    backspaceColor: KColors.teal,
                  ),
                  bottomActionBarConfig:
                      const BottomActionBarConfig(enabled: false),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: s.panel,
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// Line under the contact's name: mood → typing → online → last seen.
class _PresenceLine extends ConsumerWidget {
  final Contact contact;
  const _PresenceLine({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);

    // typing beats everything else
    ref.watch(typingProvider);
    if (ref.read(typingProvider.notifier).isTyping(contact.id)) {
      return const Text('typing…',
          style: TextStyle(
              color: Color(0xFFBFE6EC),
              fontSize: 12,
              fontWeight: FontWeight.w600));
    }

    final mood = contact.mood;
    if (mood != null && mood.trim().isNotEmpty) {
      return Text(mood,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: KColors.amberInk,
              fontSize: 12.5,
              fontWeight: FontWeight.w600));
    }

    final seen = contact.lastSeen;
    if (seen > 0) {
      final gap = nowMs() - seen;
      if (gap < 60000) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: KColors.green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            const Text('online',
                style: TextStyle(
                    color: KColors.green,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        );
      }
      return Text('last seen ${_since(gap)}',
          style: TextStyle(
              color: s.faint, fontSize: 12.5, fontWeight: FontWeight.w500));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock, size: 11, color: s.faint),
        const SizedBox(width: 3),
        Text('end-to-end encrypted',
            style: TextStyle(color: s.faint, fontSize: 12)),
      ],
    );
  }

  static String _since(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Shown instead of the composer while a contact request is still pending.
class _PendingCard extends StatelessWidget {
  final String handle;
  const _PendingCard({required this.handle});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: s.panel,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏳', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text('Waiting for $handle to accept',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: s.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                'You can message each other once your request is accepted.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.muted, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
              decoration: BoxDecoration(
                color: KColors.amberBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Request pending',
                  style: TextStyle(
                      color: KColors.amberInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}


/// Shown while a voice message is being recorded.
class _RecordingBar extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  const _RecordingBar({
    required this.seconds,
    required this.onCancel,
    required this.onStop,
  });

  String get _t {
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: KColors.danger, size: 26),
              tooltip: 'Cancel',
            ),
            Expanded(
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: s.panel,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: KColors.danger.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const _PulseDot(),
                    const SizedBox(width: 10),
                    Text('Recording  $_t',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('tap ■ to stop',
                        style: TextStyle(color: s.faint, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              onTap: onStop,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: KColors.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: KColors.danger.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.stop_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Listen to the clip before sending it.
class _PreviewBar extends StatelessWidget {
  final int seconds;
  final bool playing;
  final bool sending;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onSend;
  const _PreviewBar({
    required this.seconds,
    required this.playing,
    required this.sending,
    required this.onPlay,
    required this.onDelete,
    required this.onSend,
  });

  String get _t {
    final m = seconds ~/ 60;
    final sec = seconds % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: sending ? null : onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: KColors.danger, size: 26),
              tooltip: 'Delete',
            ),
            Expanded(
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: s.panel,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: s.line),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onPlay,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: KColors.teal,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 20),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.graphic_eq_rounded, color: s.muted, size: 20),
                    const SizedBox(width: 8),
                    Text(_t,
                        style: TextStyle(
                            color: s.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('listen, then send',
                        style: TextStyle(color: s.faint, fontSize: 11.5)),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 7),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [KColors.teal, KColors.teal2]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: KColors.teal.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(15),
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 23),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing red dot for the recording bar.
class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
            color: KColors.danger, shape: BoxShape.circle),
      ),
    );
  }
}


/// Shows which message you're replying to, above the composer.
class _ReplyBar extends StatelessWidget {
  final String who;
  final String text;
  final VoidCallback onClose;
  const _ReplyBar({
    required this.who,
    required this.text,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: KColors.teal, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to $who',
                    style: const TextStyle(
                        color: KColors.teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.muted, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: s.faint, size: 20),
          ),
        ],
      ),
    );
  }
}
