import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/api/api_client.dart';

/// Sign back in on a new phone with a username and password.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final u = _username.text.trim().replaceAll('@', '').toLowerCase();
    final p = _password.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepoProvider).recover(username: u, password: p);
      ref.read(authStateProvider.notifier).state++;
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() {
        _error = switch (e.error) {
          'no_recovery' =>
            "That account has no password set, so it can't be restored this way",
          'wrong_password' => 'Wrong password',
          'bad_username' => 'Check the username',
          'network_error' => 'Cannot reach the server',
          _ => 'Could not sign in',
        };
      });
    } catch (_) {
      setState(() => _error = 'Could not sign in');
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
        title: const Text('Sign in',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: KColors.tealSoft,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.lock_open_rounded,
                color: KColors.teal, size: 30),
          ),
          const SizedBox(height: 18),
          Text('Get your account back',
              style: TextStyle(
                  color: s.text, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Sign in with the username and password you chose. Your @username and contacts come back. Messages stay on the old phone.',
              style: TextStyle(color: s.muted, fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 24),

          TextField(
            controller: _username,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            style: TextStyle(color: s.text, fontSize: 16),
            decoration: InputDecoration(
              prefixText: '@',
              prefixStyle: TextStyle(color: s.muted, fontSize: 16),
              hintText: 'username',
              hintStyle: TextStyle(color: s.faint),
              filled: true,
              fillColor: s.panel2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_show,
            style: TextStyle(color: s.text, fontSize: 16),
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: s.faint),
              filled: true,
              fillColor: s.panel2,
              prefixIcon: Icon(Icons.lock_outline_rounded, color: s.faint),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(
                    _show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: s.faint),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: KColors.danger, fontSize: 13.5)),
          ],

          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _signIn,
              style: FilledButton.styleFrom(
                backgroundColor: KColors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white))
                  : const Text('Sign in',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KColors.amberBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline_rounded,
                    color: KColors.amberInk, size: 19),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nobody can reset your password — not even us. Without it the account cannot be recovered.',
                    style: TextStyle(
                        color: KColors.amberInk, fontSize: 12.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
