import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/crypto/kalisi_crypto.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final fingerprint =
        me != null ? KalisiCrypto.fingerprint(me.publicJwk) : '—';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
          child: Text('Privacy', style: AppTheme.display(size: 24, color: s.text)),
        ),

        // What the server can see (collapsible-style card)
        _SectionLabel('WHAT OUR SERVER CAN SEE'),
        _Card(children: [
          _Row(k: 'Phone number', v: 'Never asked', good: true),
          _Divider(),
          _Row(k: 'Contacts list', v: 'Never uploaded', good: true),
          _Divider(),
          _Row(k: 'Message content', v: 'Unreadable', good: true),
          _Divider(),
          _Row(k: 'Stored messages', v: 'Deleted on delivery'),
          _Divider(),
          _Row(k: 'Your @username', v: 'Needed to route'),
        ]),

        const SizedBox(height: 20),

        // Appearance
        _SectionLabel('APPEARANCE'),
        _Card(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Text('Dark theme',
                    style: TextStyle(color: s.text, fontSize: 15)),
                const Spacer(),
                Switch(
                  value: themeMode == ThemeMode.dark,
                  activeColor: KColors.gold,
                  onChanged: (on) => ref.read(themeModeProvider.notifier).state =
                      on ? ThemeMode.dark : ThemeMode.light,
                ),
              ],
            ),
          ),
        ]),

        const SizedBox(height: 20),

        // Encryption key
        _SectionLabel('ENCRYPTION KEY'),
        _Card(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded,
                        color: KColors.gold, size: 20),
                    const SizedBox(width: 8),
                    Text('Device key fingerprint',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'Generated and stored only on this phone. Compare it with a contact in person to verify no one is in the middle.',
                    style: TextStyle(color: s.muted, fontSize: 13, height: 1.4)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: s.panel2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(fingerprint,
                      style: TextStyle(
                          color: s.text,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ]),

        const SizedBox(height: 20),

        // Identity
        _SectionLabel('YOUR IDENTITY'),
        _Card(children: [
          _Row(k: 'Name', v: me?.name ?? '—'),
          _Divider(),
          _Row(k: 'Username', v: '@${me?.username ?? '—'}'),
          _Divider(),
          InkWell(
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
            child: _Row(k: 'Kalisi ID', v: me?.kalId ?? '—', copyable: true),
          ),
        ]),

        const SizedBox(height: 24),

        // Logout
        Material(
          color: KColors.ember.withOpacity(0.1),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => _confirmLogout(context, ref),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
              child: const Text('Log out',
                  style: TextStyle(
                      color: KColors.ember,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text('Your account lives only on this phone.',
              style: TextStyle(color: s.faint, fontSize: 12)),
        ),
      ],
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
                    color: KColors.ember, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(text,
          style: TextStyle(
              color: s.faint,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8)),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.line),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  final String k;
  final String v;
  final bool good;
  final bool copyable;
  const _Row(
      {required this.k, required this.v, this.good = false, this.copyable = false});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Text(k, style: TextStyle(color: s.text, fontSize: 14.5)),
          const Spacer(),
          if (good)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: KColors.ok.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(v,
                  style: const TextStyle(
                      color: KColors.ok,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            )
          else
            Flexible(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: s.muted, fontSize: 13.5)),
            ),
          if (copyable) ...[
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 15, color: s.faint),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Divider(height: 1, color: s.line);
  }
}
