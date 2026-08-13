import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/crypto/kalisi_crypto.dart';
import '../../widgets/avatar.dart';
import 'backup_screen.dart';

/// Settings — profile, privacy, appearance, account.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: ListView(
        children: [
          // ---- Profile header ----
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ProfileScreen(),
            )),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Avatar(
                    seed: me?.username ?? 'me',
                    label: (me?.name.isNotEmpty ?? false)
                        ? me!.name[0].toUpperCase()
                        : 'K',
                    size: 64,
                    photo: me?.avatar,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me?.name ?? '—',
                            style: TextStyle(
                                color: s.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text('@${me?.username ?? ''}',
                            style: TextStyle(color: s.muted, fontSize: 14)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: s.faint),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: s.line),

          _Group(title: 'PRIVACY', children: [
            ListTile(
              leading: const Icon(Icons.lock_rounded, color: KColors.teal),
              title: Text('Contact details are hidden',
                  style: TextStyle(color: s.text, fontSize: 15.5)),
              subtitle: Text(
                  'Phone numbers and emails in messages are always masked',
                  style: TextStyle(color: s.muted, fontSize: 12.5)),
              trailing: Icon(Icons.verified_user_rounded,
                  color: KColors.ok, size: 20),
            ),
            _Tile(
              icon: Icons.shield_outlined,
              title: 'Privacy & security',
              subtitle: 'What the server can see, your key',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PrivacyDetailsScreen(),
              )),
            ),
          ]),

          _Group(title: 'APPEARANCE', children: [
            SwitchListTile(
              value: themeMode == ThemeMode.dark,
              activeColor: KColors.teal,
              onChanged: (on) => ref.read(themeModeProvider.notifier).state =
                  on ? ThemeMode.dark : ThemeMode.light,
              secondary: Icon(Icons.dark_mode_outlined, color: KColors.teal),
              title: Text('Dark theme',
                  style: TextStyle(color: s.text, fontSize: 15.5)),
            ),
          ]),

          _Group(title: 'ACCOUNT', children: [
            _Tile(
              icon: Icons.backup_outlined,
              title: 'Backup',
              subtitle: 'Keep your account safe on this phone',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BackupScreen(),
              )),
            ),
            _Tile(
              icon: Icons.badge_outlined,
              title: 'Kalisi ID',
              subtitle: me?.kalId ?? '—',
              onTap: () {
                if (me != null) {
                  Clipboard.setData(ClipboardData(text: me.kalId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Kalisi ID copied'),
                        duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
            _Tile(
              icon: Icons.logout_rounded,
              title: 'Log out',
              danger: true,
              onTap: () => _confirmLogout(context, ref),
            ),
          ]),

          const SizedBox(height: 10),
          Center(
            child: Text('Kalisi · your account lives on this phone',
                style: TextStyle(color: s.faint, fontSize: 12)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.panel,
        title: Text('Log out?', style: TextStyle(color: s.text)),
        content: Text(
            'Your account exists only on this phone. Without a backup, logging out deletes it permanently.',
            style: TextStyle(color: s.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay', style: TextStyle(color: s.muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final me = ref.read(activePersonaProvider).valueOrNull;
              if (me != null) {
                await ref.read(dbProvider).logoutPersona(me.id);
                ref.read(authStateProvider.notifier).state++;
              }
            },
            child: const Text('Log out',
                style: TextStyle(
                    color: KColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Edit display name + profile picture.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 70,
      );
      if (file == null) return;
      setState(() => _busy = true);
      final bytes = await file.readAsBytes();
      if (bytes.length > 150000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Picture too large, try another')),
          );
        }
        return;
      }
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me == null) return;
      await ref.read(dbProvider).updateProfile(me.id, avatar: dataUrl);
      ref.invalidate(activePersonaProvider);
      await _pushToServer(avatar: dataUrl);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    await ref.read(dbProvider).updateProfile(me.id, avatar: '');
    ref.invalidate(activePersonaProvider);
    await _pushToServer(avatar: '');
  }

  Future<void> _saveName() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    setState(() => _busy = true);
    await ref.read(dbProvider).updateProfile(me.id, name: n);
    ref.invalidate(activePersonaProvider);
    await _pushToServer(name: n);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Profile updated'), duration: Duration(seconds: 2)),
      );
    }
  }

  /// Tell the server so contacts see the new name/picture.
  /// Silently ignored if the server doesn't have the endpoint yet.
  Future<void> _pushToServer({String? name, String? avatar}) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    try {
      await ref.read(apiProvider).profileUpdate(
            kalId: me.kalId,
            token: me.token,
            name: name,
            avatar: avatar,
          );
    } catch (_) {
      // server may not support it yet — local change still applies
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    if (me != null && !_loaded) {
      _name.text = me.name;
      _loaded = true;
    }

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Center(
            child: Stack(
              children: [
                Avatar(
                  seed: me?.username ?? 'me',
                  label: (me?.name.isNotEmpty ?? false)
                      ? me!.name[0].toUpperCase()
                      : 'K',
                  size: 118,
                  photo: me?.avatar,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _busy ? null : _pickPhoto,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: KColors.teal,
                        shape: BoxShape.circle,
                        border: Border.all(color: s.bg, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if ((me?.avatar ?? '').isNotEmpty)
            Center(
              child: TextButton(
                onPressed: _busy ? null : _removePhoto,
                child: const Text('Remove photo',
                    style: TextStyle(color: KColors.danger)),
              ),
            ),
          const SizedBox(height: 22),

          Text('DISPLAY NAME',
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            style: TextStyle(color: s.text, fontSize: 16),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: TextStyle(color: s.faint),
              filled: true,
              fillColor: s.panel2,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(color: KColors.teal, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('This is what your contacts see.',
              style: TextStyle(color: s.faint, fontSize: 12.5)),

          const SizedBox(height: 20),
          Text('USERNAME',
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              color: s.panel2,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text('@${me?.username ?? ''}',
                style: TextStyle(color: s.muted, fontSize: 16)),
          ),

          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [KColors.teal, KColors.teal2]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _busy ? null : _saveName,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white))
                          : const Text('Save',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                    ),
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

/// Privacy details, now living inside Settings.
class PrivacyDetailsScreen extends ConsumerWidget {
  const PrivacyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    final fingerprint =
        me != null ? KalisiCrypto.fingerprint(me.publicJwk) : '—';

    return Scaffold(
      backgroundColor: s.bg,
      appBar: AppBar(
        backgroundColor: s.panel,
        title: const Text('Privacy & security',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: KColors.tealSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: KColors.teal, size: 19),
                    SizedBox(width: 8),
                    Text('What our server can see',
                        style: TextStyle(
                            color: KColors.teal,
                            fontWeight: FontWeight.w800,
                            fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                _Fact(k: 'Phone number', v: 'Never asked', good: true),
                _Fact(k: 'Contacts list', v: 'Never uploaded', good: true),
                _Fact(k: 'Message content', v: 'Unreadable', good: true),
                _Fact(k: 'Stored messages', v: 'Deleted on delivery'),
                _Fact(k: 'Your @username', v: 'Needed to route'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('DEVICE KEY FINGERPRINT',
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
            child: Text(fingerprint,
                style: TextStyle(
                    color: s.text,
                    fontFamily: 'monospace',
                    fontSize: 14,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 8),
          Text(
              'Generated and stored only on this phone. Compare it with a contact in person to be sure no one is in the middle.',
              style: TextStyle(color: s.muted, fontSize: 13, height: 1.45)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String k;
  final String v;
  final bool good;
  const _Fact({required this.k, required this.v, this.good = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                style: const TextStyle(
                    color: Color(0xFF16201F), fontSize: 14)),
          ),
          Text(v,
              style: TextStyle(
                  color: good ? const Color(0xFF1E8449) : KColors.teal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(title,
              style: TextStyle(
                  color: s.faint,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7)),
        ),
        ...children,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final c = danger ? KColors.danger : KColors.teal;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(title,
          style: TextStyle(
              color: danger ? KColors.danger : s.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: s.muted, fontSize: 13)),
      trailing: danger
          ? null
          : Icon(Icons.chevron_right_rounded, color: s.faint),
      onTap: onTap,
    );
  }
}
