import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';

/// Your account is a private key held only on this phone.
/// Backup writes it to a file; restore reads one back.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _backup() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      final payload = jsonEncode({
        'v': 1,
        'app': 'kalisi',
        'kal_id': me.kalId,
        'username': me.username,
        'name': me.name,
        'token': me.token,
        'priv': me.privateJwk,
        'pub': me.publicJwk,
        'avatar': me.avatar,
        'saved_at': DateTime.now().toIso8601String(),
      });

      final dir = await getApplicationDocumentsDirectory();
      final safeName = me.username.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
      final path = '${dir.path}/kalisi-backup-$safeName.kalisi';
      final file = File(path);
      await file.writeAsString(payload, flush: true);

      if (!mounted) return;
      // hand it to the user so they can put it in Drive, Files, anywhere
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        subject: 'Kalisi account backup',
        text:
            'Keep this file safe and private — it restores your Kalisi account.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup file created')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the backup')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Backup & restore',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KColors.amberBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: KColors.amberInk, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your account lives only on this phone. Without a backup, losing the phone means losing the account — nobody can recover it, not even us.',
                    style: TextStyle(
                        color: KColors.amberInk, fontSize: 13.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _Card(
            icon: Icons.backup_rounded,
            title: 'Back up my account',
            body:
                'Saves a backup file you can keep in Google Drive, Files, or send to yourself.',
            button: 'Create backup',
            busy: _busy,
            onTap: me == null ? null : _backup,
          ),
          const SizedBox(height: 14),
          _Card(
            icon: Icons.restore_rounded,
            title: 'Restore from a backup',
            body:
                'Pick a .kalisi backup file to bring your account back on this phone.',
            button: 'Choose backup file',
            busy: false,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const RestoreScreen(),
            )),
          ),

          const SizedBox(height: 22),
          Text(
              'The backup holds your identity key. Anyone with the file can use your account, so keep it private. Messages are not included — only your identity, so friends still recognise you.',
              style: TextStyle(color: s.muted, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String button;
  final bool busy;
  final VoidCallback? onTap;
  const _Card({
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: KColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: KColors.teal, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: s.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body,
              style: TextStyle(color: s.muted, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: KColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white))
                  : Text(button,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pick a backup file and bring the account back.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});
  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _pickAndRestore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }
      final raw = await File(path).readAsString();
      await _restoreFrom(raw);
    } catch (_) {
      setState(() {
        _busy = false;
        _error = "That file couldn't be read";
      });
    }
  }

  Future<void> _restoreFrom(String raw) async {
    try {
      var text = raw.trim();
      // also accept the older pasted-code format
      if (text.startsWith('KALISI1:')) {
        text = utf8.decode(base64Decode(text.substring('KALISI1:'.length)));
      }
      final json = jsonDecode(text) as Map<String, dynamic>;

      final kalId = json['kal_id']?.toString();
      final priv = json['priv']?.toString();
      final pub = json['pub']?.toString();
      final token = json['token']?.toString();
      if (kalId == null || priv == null || pub == null || token == null) {
        throw const FormatException('incomplete backup');
      }

      await ref.read(dbProvider).upsertPersona(PersonasCompanion(
            id: Value(newUuid()),
            kalId: Value(kalId),
            username: Value(json['username']?.toString() ?? ''),
            name: Value(json['name']?.toString() ?? ''),
            token: Value(token),
            privateJwk: Value(priv),
            publicJwk: Value(pub),
            avatar: Value(json['avatar']?.toString()),
            createdAt: Value(nowMs()),
            active: const Value(true),
          ));
      ref.read(authStateProvider.notifier).state++;

      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account restored')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "That doesn't look like a Kalisi backup";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Restore account',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_rounded, size: 64, color: s.faint),
            const SizedBox(height: 18),
            Text('Choose your backup file',
                style: TextStyle(
                    color: s.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'Find the .kalisi file you saved from your old phone. Your @username and contacts come back; messages stay on the old phone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: s.muted, fontSize: 13.5, height: 1.5)),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  style: const TextStyle(
                      color: KColors.danger, fontSize: 13.5)),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _pickAndRestore,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.folder_open_rounded, size: 19),
                label: const Text('Choose file',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                style: FilledButton.styleFrom(
                  backgroundColor: KColors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
