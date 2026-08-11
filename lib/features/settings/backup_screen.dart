import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';

/// Your account is a private key that exists only on this phone.
/// This screen lets you copy it somewhere safe and put it back later.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _revealed = false;

  String _buildBackup(Persona me) {
    final payload = {
      'v': 1,
      'kal_id': me.kalId,
      'username': me.username,
      'name': me.name,
      'token': me.token,
      'priv': me.privateJwk,
      'pub': me.publicJwk,
    };
    return 'KALISI1:${base64Encode(utf8.encode(jsonEncode(payload)))}';
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    final code = me == null ? '' : _buildBackup(me);

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Backup & restore',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
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
                    'Your account lives only on this phone. If you lose it without a backup, the account and its messages are gone for good — nobody can recover them, not even us.',
                    style: TextStyle(
                        color: KColors.amberInk, fontSize: 13.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          Text('YOUR BACKUP CODE',
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: s.panel2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _revealed
                  ? code
                  : '•' * 60,
              style: TextStyle(
                  color: s.text,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _revealed = !_revealed),
                  icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18),
                  label: Text(_revealed ? 'Hide' : 'Reveal'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KColors.teal,
                    side: const BorderSide(color: KColors.teal),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: me == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Backup code copied — paste it somewhere safe')),
                          );
                        },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KColors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              'Keep this code private — anyone who has it can use your account. Save it in a password manager or somewhere only you can reach.',
              style: TextStyle(color: s.muted, fontSize: 12.5, height: 1.45)),

          const SizedBox(height: 30),
          Divider(color: s.line),
          const SizedBox(height: 18),

          Text('RESTORE ON A NEW PHONE',
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Text(
              'Install Kalisi, open this screen from the welcome page, and paste your backup code. Your @username and contacts come back. Old messages stay on the old phone.',
              style: TextStyle(color: s.muted, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const RestoreScreen(),
            )),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restore from a backup code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: KColors.teal,
              side: const BorderSide(color: KColors.teal),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paste a backup code to bring an account back.
class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});
  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final raw = _code.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!raw.startsWith('KALISI1:')) {
        throw const FormatException('not a Kalisi backup code');
      }
      final json = jsonDecode(
          utf8.decode(base64Decode(raw.substring('KALISI1:'.length))));
      final kalId = json['kal_id']?.toString();
      final priv = json['priv']?.toString();
      final pub = json['pub']?.toString();
      final token = json['token']?.toString();
      if (kalId == null || priv == null || pub == null || token == null) {
        throw const FormatException('incomplete backup code');
      }

      final db = ref.read(dbProvider);
      await db.upsertPersona(PersonasCompanion(
        id: Value(newUuid()),
        kalId: Value(kalId),
        username: Value(json['username']?.toString() ?? ''),
        name: Value(json['name']?.toString() ?? ''),
        token: Value(token),
        privateJwk: Value(priv),
        publicJwk: Value(pub),
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
      setState(() => _error = "That code doesn't look right");
    } finally {
      if (mounted) setState(() => _busy = false);
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Text('Paste the backup code from your other phone.',
              style: TextStyle(color: s.muted, fontSize: 14, height: 1.45)),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            maxLines: 5,
            style: TextStyle(
                color: s.text, fontFamily: 'monospace', fontSize: 12.5),
            decoration: InputDecoration(
              hintText: 'KALISI1:…',
              hintStyle: TextStyle(color: s.faint),
              filled: true,
              fillColor: s.panel2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: const TextStyle(color: KColors.danger, fontSize: 13)),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _restore,
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
                : const Text('Restore',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          const SizedBox(height: 14),
          Text(
              'Restoring replaces whatever account is on this phone. Messages are not transferred — only your identity, so friends still recognise you.',
              style: TextStyle(color: s.faint, fontSize: 12.5, height: 1.45)),
        ],
      ),
    );
  }
}
