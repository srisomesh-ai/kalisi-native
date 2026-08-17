import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../util/ids.dart';
import '../../util/buzz.dart';
import 'status_model.dart';

/// Sheet offering the status types, then the right composer for each.
class StatusComposer {
  static Future<void> open(BuildContext context, WidgetRef ref) async {
    final s = KScheme.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add to your status',
                  style: TextStyle(
                      color: s.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Type(
                    label: 'Text',
                    icon: Icons.text_fields_rounded,
                    colors: const [Color(0xFF6C5CE7), Color(0xFF3F32B0)],
                    onTap: () => Navigator.pop(ctx, 'text'),
                  ),
                  _Type(
                    label: 'Photo',
                    icon: Icons.photo_camera_rounded,
                    colors: const [KColors.teal2, KColors.teal],
                    onTap: () => Navigator.pop(ctx, 'photo'),
                  ),
                  _Type(
                    label: 'Voice',
                    icon: Icons.mic_rounded,
                    colors: const [KColors.amber, Color(0xFFD9720F)],
                    onTap: () => Navigator.pop(ctx, 'voice'),
                  ),
                  _Type(
                    label: 'Video',
                    icon: Icons.videocam_rounded,
                    colors: const [Color(0xFFE4739A), Color(0xFFB03A63)],
                    onTap: () => Navigator.pop(ctx, 'video'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'text':
        await _postText(context, ref);
        break;
      case 'photo':
        await _postPhoto(context, ref);
        break;
      case 'voice':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const VoiceStatusScreen(),
        ));
        break;
      case 'video':
        await _postVideo(context, ref);
        break;
    }
  }

  // ---------- text ----------

  static Future<void> _postText(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final s = KScheme.of(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share an update',
                style: TextStyle(
                    color: s.text, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 400,
              style: TextStyle(color: s.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: TextStyle(color: s.faint),
                filled: true,
                fillColor: s.panel2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: KColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Share',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
    if (text == null || text.isEmpty) return;
    await _post(context, ref, type: 'text', payload: text);
  }

  // ---------- photo ----------

  static Future<void> _postPhoto(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 72,
      );
      if (file == null || !context.mounted) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 900000) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That photo is too large')),
          );
        }
        return;
      }

      // Caption it, and optionally put a track behind it.
      final result = await Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => PhotoStatusScreen(imageBytes: bytes),
        ),
      );
      if (result == null || !context.mounted) return;   // cancelled

      final music = result['audio'] ?? '';
      final caption = result['caption'] ?? '';
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      if (music.isEmpty && caption.isEmpty) {
        await _post(context, ref, type: 'photo', payload: dataUrl);
      } else {
        // photo, caption and track travel together as one payload
        final combined = jsonEncode({
          'img': dataUrl,
          if (music.isNotEmpty) 'audio': music,
          if (caption.isNotEmpty) 'caption': caption,
        });
        await _post(context, ref,
            type: 'photo', payload: 'mix:${base64Encode(utf8.encode(combined))}');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add that photo')),
        );
      }
    }
  }

  // ---------- video ----------

  static Future<void> _postVideo(BuildContext context, WidgetRef ref) async {
    final s = KScheme.of(context);
    final src = await showModalBottomSheet<ImageSource>(
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
              leading: const Icon(Icons.video_library_rounded,
                  color: KColors.teal),
              title: Text('Choose a video', style: TextStyle(color: s.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_rounded, color: KColors.teal),
              title: Text('Record a video', style: TextStyle(color: s.text)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (src == null || !context.mounted) return;

    try {
      final picked = await ImagePicker().pickVideo(
        source: src,
        maxDuration: const Duration(seconds: 30),
      );
      if (picked == null || !context.mounted) return;

      // Show progress — compressing a video takes a moment.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _Working(text: 'Preparing your video…'),
      );

      MediaInfo? info;
      try {
        info = await VideoCompress.compressVideo(
          picked.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: true,
        );
      } catch (_) {}

      final path = info?.path ?? picked.path;
      if (context.mounted) Navigator.of(context).pop(); // close progress
      if (!context.mounted) return;

      // Watch it back and confirm before it goes out.
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => VideoPreviewScreen(path: path)),
      );
      if (ok != true || !context.mounted) return;

      final bytes = await File(path).readAsBytes();
      // ~19MB of actual video; base64 adds about a third
      if (bytes.length > 19000000) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('That video is too long — try under 30 seconds')),
          );
        }
        return;
      }

      final dataUrl = 'data:video/mp4;base64,${base64Encode(bytes)}';
      if (!context.mounted) return;
      await _post(context, ref, type: 'video', payload: dataUrl);
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not use that video')),
        );
      }
    }
  }

  // ---------- shared post ----------

  static Future<void> _post(
    BuildContext context,
    WidgetRef ref, {
    required String type,
    required String payload,
  }) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    try {
      await ref.read(apiProvider).statusPost(
            kalId: me.kalId,
            token: me.token,
            type: type,
            payload: payload,
          );
      ref.read(statusRefreshProvider.notifier).state++;
      Buzz.statusPosted();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to your status')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share that')),
        );
      }
    }
  }
}

class _Type extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _Type({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: s.panel2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      color: s.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Record a voice status, listen back, then share.
class VoiceStatusScreen extends ConsumerStatefulWidget {
  const VoiceStatusScreen({super.key});
  @override
  ConsumerState<VoiceStatusScreen> createState() => _VoiceStatusScreenState();
}

class _VoiceStatusScreenState extends ConsumerState<VoiceStatusScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _recording = false;
  bool _playing = false;
  bool _busy = false;
  String? _path;
  int _secs = 0;

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final p = await _recorder.stop();
      setState(() {
        _recording = false;
        _path = p;
      });
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission needed')),
        );
      }
      return;
    }
    final p = '${Directory.systemTemp.path}/kstatus_${nowMs()}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: p,
    );
    setState(() {
      _recording = true;
      _secs = 0;
      _path = null;
    });
    // simple ticker
    while (mounted && _recording) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_recording) break;
      setState(() => _secs++);
      if (_secs >= 60) await _toggleRecord(); // cap at a minute
    }
  }

  Future<void> _togglePlay() async {
    if (_path == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    await _player.play(DeviceFileSource(_path!));
    setState(() => _playing = true);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  Future<void> _share() async {
    final p = _path;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(p).readAsBytes();
      if (bytes.length > 900000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That recording is too long')),
          );
        }
        return;
      }
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(apiProvider).statusPost(
            kalId: me.kalId,
            token: me.token,
            type: 'voice',
            payload: 'data:audio/mp4;base64,${base64Encode(bytes)}',
          );
      ref.read(statusRefreshProvider.notifier).state++;
      Buzz.statusPosted();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice status shared')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share that')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _time {
    final m = _secs ~/ 60;
    final s = _secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Voice status',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _recording
                  ? _time
                  : (_path == null ? 'Tap to record' : 'Ready to share'),
              style: TextStyle(
                  color: s.text, fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _recording
                  ? 'Tap again to stop · up to 1 minute'
                  : (_path == null
                      ? 'Say something for your friends'
                      : 'Listen back, then share'),
              style: TextStyle(color: s.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _toggleRecord,
              child: Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _recording
                        ? const [KColors.danger, Color(0xFFB93B2C)]
                        : const [KColors.amber, Color(0xFFD9720F)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_recording ? KColors.danger : KColors.amber)
                          .withOpacity(0.4),
                      blurRadius: 26,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 46),
              ),
            ),
            const SizedBox(height: 40),
            if (_path != null && !_recording) ...[
              OutlinedButton.icon(
                onPressed: _togglePlay,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 20),
                label: Text(_playing ? 'Pause' : 'Listen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: KColors.teal,
                  side: const BorderSide(color: KColors.teal),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 26, vertical: 13),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _share,
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
                      : const Text('Share to status',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


/// Simple blocking progress dialog.
class _Working extends StatelessWidget {
  final String text;
  const _Working({required this.text});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Dialog(
      backgroundColor: s.panel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: KColors.teal),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text(text,
                  style: TextStyle(color: s.text, fontSize: 14.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preview a photo status and optionally put a track behind it.
///
/// Returns '' for no music, a base64 audio data URL if a track was chosen,
/// or null if cancelled.
class PhotoStatusScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const PhotoStatusScreen({super.key, required this.imageBytes});

  @override
  State<PhotoStatusScreen> createState() => _PhotoStatusScreenState();
}

class _PhotoStatusScreenState extends State<PhotoStatusScreen> {
  final _player = AudioPlayer();
  final _caption = TextEditingController();
  String? _trackName;
  String? _trackData;
  bool _playing = false;
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    setState(() => _busy = true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = res?.files.single.path;
      final name = res?.files.single.name;
      if (path == null) return;

      final bytes = await File(path).readAsBytes();
      // a status carries its audio, so keep it short
      if (bytes.length > 1200000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Track too large — try a shorter clip')),
          );
        }
        return;
      }
      setState(() {
        _trackName = name;
        _trackData = 'data:audio/mpeg;base64,${base64Encode(bytes)}';
      });
      await _player.play(DeviceFileSource(path));
      setState(() => _playing = true);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not use that track')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.resume();
      setState(() => _playing = true);
    }
  }

  void _clear() {
    _player.stop();
    setState(() {
      _trackName = null;
      _trackData = null;
      _playing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Your update'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
            ),
          ),
          // music strip
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(
                    _trackName == null
                        ? Icons.music_note_rounded
                        : (_playing
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded),
                    color: KColors.amber,
                    size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: _busy
                      ? const Text('Loading…',
                          style: TextStyle(color: Colors.white70))
                      : Text(
                          _trackName ?? 'Add music from your phone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _trackName == null
                                  ? Colors.white70
                                  : Colors.white,
                              fontSize: 14.5,
                              fontWeight: _trackName == null
                                  ? FontWeight.w400
                                  : FontWeight.w600),
                        ),
                ),
                if (_trackName == null)
                  TextButton(
                    onPressed: _busy ? null : _pickMusic,
                    child: const Text('Choose',
                        style: TextStyle(color: KColors.amber)),
                  )
                else ...[
                  IconButton(
                    onPressed: _toggle,
                    icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _clear,
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          // caption
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _caption,
                maxLines: 3,
                minLines: 1,
                maxLength: 200,
                style: const TextStyle(color: Colors.white, fontSize: 15.5),
                decoration: const InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle: TextStyle(color: Colors.white60),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop({
                    'audio': _trackData ?? '',
                    'caption': _caption.text.trim(),
                  }),
                  icon: const Icon(Icons.send_rounded, size: 19),
                  label: const Text('Share to status',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  style: FilledButton.styleFrom(
                    backgroundColor: KColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Watch a video back before sharing it.
class VideoPreviewScreen extends StatefulWidget {
  final String path;
  const VideoPreviewScreen({super.key, required this.path});
  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  VideoPlayerController? _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      _c = c;
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  String get _length {
    final d = _c?.value.duration ?? Duration.zero;
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final playing = _c?.value.isPlaying ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Your video'),
        actions: [
          if (_ready && _c != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(_length,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13.5)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: !_ready
                  ? const CircularProgressIndicator(color: Colors.white)
                  : (_c?.value.isInitialized ?? false)
                      ? GestureDetector(
                          onTap: _toggle,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AspectRatio(
                                aspectRatio: _c!.value.aspectRatio,
                                child: VideoPlayer(_c!),
                              ),
                              if (!playing)
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded,
                                      color: Colors.white, size: 34),
                                ),
                            ],
                          ),
                        )
                      : const Text('Could not play this video',
                          style: TextStyle(color: Colors.white70)),
            ),
          ),
          if (_c?.value.isInitialized ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: VideoProgressIndicator(
                _c!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: KColors.teal,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: const Text('Choose another'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.send_rounded, size: 19),
                      label: const Text('Share to status',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15.5)),
                      style: FilledButton.styleFrom(
                        backgroundColor: KColors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
