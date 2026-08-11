import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/crypto/kalisi_crypto.dart';
import '../../data/db/database.dart';
import '../../util/ids.dart';
import '../../widgets/avatar.dart';

/// Details for one contact — opened by tapping their photo.
class ContactDetailsScreen extends ConsumerWidget {
  final Contact contact;
  const ContactDetailsScreen({super.key, required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final fingerprint = contact.publicJwk != null
        ? KalisiCrypto.fingerprint(contact.publicJwk!)
        : '—';

    return Scaffold(
      backgroundColor: s.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: KColors.teal,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(contact.name,
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
                    padding: const EdgeInsets.only(bottom: 26),
                    child: GestureDetector(
                      onTap: () => _viewPhoto(context),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white24, width: 3),
                        ),
                        child: Avatar(
                          seed: contact.kalId,
                          label: contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          size: 118,
                          photo: contact.avatar,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 12),

              // presence / mood
              Center(
                child: _PresenceChip(contact: contact),
              ),
              const SizedBox(height: 18),

              _Section('ABOUT'),
              _Row(
                icon: Icons.alternate_email_rounded,
                label: 'Username',
                value: contact.username != null
                    ? '@${contact.username}'
                    : 'not set',
                onCopy: contact.username != null
                    ? () => _copy(context, '@${contact.username}')
                    : null,
              ),
              _Row(
                icon: Icons.badge_outlined,
                label: 'Kalisi ID',
                value: contact.kalId,
                onCopy: () => _copy(context, contact.kalId),
              ),

              _Section('SECURITY'),
              _Row(
                icon: Icons.vpn_key_outlined,
                label: 'Key fingerprint',
                value: fingerprint,
                mono: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: Text(
                    'Compare this with ${contact.name} in person to be sure no one is in the middle.',
                    style:
                        TextStyle(color: s.faint, fontSize: 12.5, height: 1.4)),
              ),

              const SizedBox(height: 24),
              _Danger(
                icon: contact.blocked
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                label: contact.blocked
                    ? 'Unblock ${contact.name}'
                    : 'Block ${contact.name}',
                onTap: () => _toggleBlock(context, ref),
              ),
              _Danger(
                icon: Icons.delete_outline_rounded,
                label: 'Clear this chat',
                onTap: () => _confirmClear(context, ref),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String v) {
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  void _viewPhoto(BuildContext context) {
    final bytes = Avatar.decode(contact.avatar);
    if (bytes == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(contact.name),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Future<void> _toggleBlock(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final me = ref.read(activePersonaProvider).valueOrNull;
    final nowBlocked = !contact.blocked;
    await db.setBlocked(contact.id, nowBlocked);
    if (me != null) {
      try {
        await ref.read(apiProvider).call(
          nowBlocked ? 'block' : 'unblock',
          {
            'kal_id': me.kalId,
            'token': me.token,
            'target': contact.kalId,
          },
        );
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nowBlocked
              ? '${contact.name} blocked'
              : '${contact.name} unblocked'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.panel,
        title: Text('Clear this chat?', style: TextStyle(color: s.text)),
        content: Text(
            'All messages with ${contact.name} will be removed from this phone.',
            style: TextStyle(color: s.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: s.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(dbProvider).clearMessages(contact.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat cleared')),
                );
              }
            },
            child: const Text('Clear',
                style: TextStyle(
                    color: KColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _PresenceChip extends StatelessWidget {
  final Contact contact;
  const _PresenceChip({required this.contact});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final mood = contact.mood;
    if (mood != null && mood.trim().isNotEmpty) {
      return _chip(mood, KColors.amberBg, KColors.amberInk);
    }
    final seen = contact.lastSeen;
    if (seen > 0) {
      final gap = nowMs() - seen;
      if (gap < 60000) {
        return _chip('online', KColors.okBg, const Color(0xFF1E8449));
      }
      final d = Duration(milliseconds: gap);
      final ago = d.inMinutes < 60
          ? '${d.inMinutes} min ago'
          : (d.inHours < 24 ? '${d.inHours} h ago' : '${d.inDays} d ago');
      return _chip('last seen $ago', s.panel2, s.muted);
    }
    return _chip('🔒 end-to-end encrypted', KColors.tealSoft, KColors.teal);
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(title,
          style: TextStyle(
              color: s.faint,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7)),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool mono;
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
    this.mono = false,
  });
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return ListTile(
      leading: Icon(icon, color: KColors.teal, size: 22),
      title: Text(label, style: TextStyle(color: s.muted, fontSize: 12.5)),
      subtitle: Text(value,
          style: TextStyle(
              color: s.text,
              fontSize: mono ? 14 : 15.5,
              fontWeight: FontWeight.w600,
              fontFamily: mono ? 'monospace' : null,
              letterSpacing: mono ? 1 : null)),
      trailing: onCopy == null
          ? null
          : IconButton(
              onPressed: onCopy,
              icon: Icon(Icons.copy_rounded, size: 18, color: s.faint),
            ),
    );
  }
}

class _Danger extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Danger(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: KColors.danger),
      title: Text(label,
          style: const TextStyle(
              color: KColors.danger,
              fontSize: 15.5,
              fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }
}
