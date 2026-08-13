import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';

/// Automatic backup: one fixed file, written without asking, found again
/// without asking. Repeat backups overwrite the same file.
class BackupStore {
  static const _fileName = 'kalisi-account.backup';

  /// A folder the app can always write to, with no permission prompt, that
  /// survives app updates. On Android this sits under
  /// Android/data/com.messenger.app/files/KalisiBackup.
  static Future<Directory> _dir() async {
    Directory base;
    try {
      final ext = await getExternalStorageDirectory();
      base = ext ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/KalisiBackup');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> file() async =>
      File('${(await _dir()).path}/$_fileName');

  /// Write (or overwrite) the backup. Returns the file.
  static Future<File> save(Persona me) async {
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
    final f = await file();
    await f.writeAsString(payload, flush: true);
    return f;
  }

  /// Is there a backup sitting there already?
  static Future<File?> find() async {
    try {
      final f = await file();
      if (f.existsSync() && f.lengthSync() > 20) return f;
    } catch (_) {}
    return null;
  }

  static Future<DateTime?> savedAt() async {
    final f = await find();
    if (f == null) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return DateTime.tryParse('${j['saved_at']}') ?? f.lastModifiedSync();
    } catch (_) {
      return f.lastModifiedSync();
    }
  }

  /// Restore straight from the saved file.
  static Future<bool> restore(WidgetRef ref, {String? fromText}) async {
    try {
      final text = fromText ?? await (await find())?.readAsString();
      if (text == null) return false;

      var body = text.trim();
      if (body.startsWith('KALISI1:')) {
        body = utf8.decode(base64Decode(body.substring('KALISI1:'.length)));
      }
      final j = jsonDecode(body) as Map<String, dynamic>;

      final kalId = j['kal_id']?.toString();
      final priv = j['priv']?.toString();
      final pub = j['pub']?.toString();
      final token = j['token']?.toString();
      if (kalId == null || priv == null || pub == null || token == null) {
        return false;
      }

      await ref.read(dbProvider).upsertPersona(PersonasCompanion(
            id: Value(newUuid()),
            kalId: Value(kalId),
            username: Value(j['username']?.toString() ?? ''),
            name: Value(j['name']?.toString() ?? ''),
            token: Value(token),
            privateJwk: Value(priv),
            publicJwk: Value(pub),
            avatar: Value(j['avatar']?.toString()),
            createdAt: Value(nowMs()),
            active: const Value(true),
          ));
      ref.read(authStateProvider.notifier).state++;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Backup screen — one button to save, one to restore. No folder pickers.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  DateTime? _savedAt;
  String? _path;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final at = await BackupStore.savedAt();
    final f = await BackupStore.find();
    if (!mounted) return;
    setState(() {
      _savedAt = at;
      _path = f?.path;
    });
  }

  Future<void> _backupNow() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    try {
      await BackupStore.save(me);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backed up')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the backup')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Optional extra copy, in case the phone is lost entirely.
  Future<void> _exportCopy() async {
    final f = await BackupStore.find();
    if (f == null) {
      await _backupNow();
    }
    final file = await BackupStore.find();
    if (file == null || !mounted) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Kalisi account backup',
      text: 'Keep this private — it restores your Kalisi account.',
    );
  }

  String _when(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final has = _savedAt != null;

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Backup',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          // state card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: has
                    ? [KColors.teal, KColors.teal2]
                    : [const Color(0xFF8A9A98), const Color(0xFF6E7E7C)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      has
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      color: Colors.white,
                      size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(has ? 'Backed up' : 'Not backed up yet',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                          has
                              ? 'Last saved ${_when(_savedAt!)}'
                              : 'Tap below to save your account',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.78),
                              fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _backupNow,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white))
                  : const Icon(Icons.backup_rounded, size: 20),
              label: Text(has ? 'Back up again' : 'Back up now',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: KColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              'Saved automatically on this phone. Backing up again overwrites the previous copy.',
              style: TextStyle(color: s.muted, fontSize: 12.5, height: 1.45)),

          const SizedBox(height: 24),
          Divider(color: s.line),
          const SizedBox(height: 16),

          Text('KEEP A COPY ELSEWHERE',
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Text(
              'The backup lives on this phone, so it goes with the phone. Send a copy to Drive or yourself so you can get your account back if the phone is lost.',
              style: TextStyle(color: s.muted, fontSize: 13, height: 1.45)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _exportCopy,
            icon: const Icon(Icons.ios_share_rounded, size: 19),
            label: const Text('Send a copy'),
            style: OutlinedButton.styleFrom(
              foregroundColor: KColors.teal,
              side: const BorderSide(color: KColors.teal),
              minimumSize: const Size.fromHeight(48),
            ),
          ),

          if (_path != null) ...[
            const SizedBox(height: 20),
            Text('Saved at',
                style: TextStyle(
                    color: s.faint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7)),
            const SizedBox(height: 5),
            Text(_path!,
                style: TextStyle(
                    color: s.muted, fontSize: 11, fontFamily: 'monospace')),
          ],

          const SizedBox(height: 22),
          Text(
              'The backup holds your identity key — anyone with it can use your account. Messages are not included, only your identity, so friends still recognise you.',
              style: TextStyle(color: s.faint, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }
}
