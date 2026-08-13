import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../settings/backup_screen.dart';
import '../../app/providers.dart';
import '../../data/api/api_client.dart';
import '../../widgets/k_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  bool _busy = false;
  bool _foundBackup = false;
  String? _backupWho;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lookForBackup();
  }

  /// Look for a backup this phone already holds, so a returning user
  /// doesn't have to hunt for a file.
  Future<void> _lookForBackup() async {
    try {
      final f = await BackupStore.find();
      if (f == null || !mounted) return;
      String? who;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        who = j['username']?.toString();
      } catch (_) {}
      setState(() {
        _foundBackup = true;
        _backupWho = who;
      });
    } catch (_) {}
  }

  Future<void> _restoreFound() async {
    setState(() => _busy = true);
    final ok = await BackupStore.restore(ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That backup could not be read')),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    final username =
        _username.text.trim().replaceAll('@', '').toLowerCase();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(username)) {
      setState(() => _error = 'Username: 3–20 letters, numbers or _');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepoProvider)
          .createIdentity(name: name, username: username);
      ref.read(authStateProvider.notifier).state++;
      // save a backup straight away so the account is never unprotected
      try {
        final me = await ref.read(dbProvider).activePersona();
        if (me != null) await BackupStore.save(me);
      } catch (_) {}
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = switch (e.error) {
          'username_taken' => '@$username is already taken',
          'bad_username' => 'Username must be 3–20 letters, numbers or _',
          'bad_input' => 'Invalid details — please check and retry',
          'network_error' => 'Cannot reach the server. Check your internet.',
          _ => 'Could not create account (${e.error})',
        };
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Something went wrong: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [KColors.gold, KColors.ember]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text('KALISI',
                      style: TextStyle(
                        color: KColors.gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 3,
                      )),
                ],
              ),
              const SizedBox(height: 20),
              Text('Welcome to\nKalisi.',
                  style: AppTheme.display(size: 40, color: s.text)),
              const SizedBox(height: 14),
              _Point(text: 'No phone number needed. Just pick a @username.'),
              _Point(text: 'Encrypted end to end. Only you and your contact can read chats.'),
              _Point(text: 'Your account lives on this phone, backed up only by you.'),
              const SizedBox(height: 22),
              _Field(label: 'YOUR NAME', controller: _name, hint: 'e.g. Somesh'),
              const SizedBox(height: 14),
              _Field(
                label: 'CHOOSE YOUR @USERNAME',
                controller: _username,
                hint: 'username',
                prefix: '@',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: KColors.ember, fontSize: 13.5)),
              ],
              const SizedBox(height: 20),
              KButton(
                label: _busy ? 'Creating…' : 'Create my Kalisi ID',
                onPressed: _busy ? null : _create,
                loading: _busy,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('No OTP, no SIM, no email to verify.',
                    style: TextStyle(color: s.faint, fontSize: 12.5)),
              ),
              // A backup found on this phone — one tap to come back.
              if (_foundBackup) ...[
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: Divider(color: s.line)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(color: s.faint, fontSize: 12.5)),
                    ),
                    Expanded(child: Divider(color: s.line)),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KColors.tealSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.restore_rounded,
                              color: KColors.teal, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Account found on this phone',
                                    style: TextStyle(
                                        color: KColors.teal,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                if (_backupWho != null)
                                  Text('@$_backupWho',
                                      style: TextStyle(
                                          color: KColors.teal.withOpacity(0.8),
                                          fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _restoreFound,
                          style: FilledButton.styleFrom(
                            backgroundColor: KColors.teal,
                            padding:
                                const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Restore my account',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final String text;
  const _Point({required this.text});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 6,
            height: 6,
            decoration:
                const BoxDecoration(color: KColors.gold, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(text,
                style: TextStyle(color: s.muted, fontSize: 14.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final String? prefix;
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: s.faint,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          style: TextStyle(color: s.text, fontSize: 16),
          textCapitalization: prefix == '@'
              ? TextCapitalization.none
              : TextCapitalization.words,
          decoration: InputDecoration(
            prefixText: prefix,
            prefixStyle: TextStyle(color: s.muted, fontSize: 16),
            hintText: hint,
            hintStyle: TextStyle(color: s.faint),
            filled: true,
            fillColor: s.panel,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: s.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: KColors.gold, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
