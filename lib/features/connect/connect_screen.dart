import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/contacts_repository.dart';

/// Incoming contact requests for the active persona.
final requestsProvider = FutureProvider<List<IncomingRequest>>((ref) async {
  ref.watch(requestsRefreshProvider);
  ref.watch(requestsTickProvider);   // refreshes every few seconds
  final me = await ref.watch(activePersonaProvider.future);
  if (me == null) return const [];
  try {
    return await ref.watch(contactsRepoProvider).incomingRequests(me);
  } catch (_) {
    return const [];
  }
});

/// Bump to refresh requests.
final requestsRefreshProvider = StateProvider<int>((ref) => 0);

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _username = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _msgOk = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    final handle = _username.text.trim().replaceAll('@', '');
    if (handle.isEmpty) return;
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;

    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final contact = await ref.read(contactsRepoProvider).addFriend(me, handle);
      setState(() {
        _busy = false;
        _msgOk = true;
        _msg = contact.verified
            ? 'Connected with ${contact.name}!'
            : 'Request sent to @$handle';
        _username.clear();
      });
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _msgOk = false;
        _msg = switch (e.error) {
          'not_found' => 'No user found with @$handle',
          'thats_you' => "That's your own username",
          'network_error' => 'Cannot reach the server',
          _ => 'Could not add (${e.error})',
        };
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _msgOk = false;
        _msg = 'Something went wrong';
      });
    }
  }

  Future<void> _act(IncomingRequest req, bool accept) async {
    final me = ref.read(activePersonaProvider).valueOrNull;
    if (me == null) return;
    try {
      await ref.read(contactsRepoProvider).actOnRequest(me, req, accept);
      ref.read(requestsRefreshProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(accept
              ? 'Connected with ${req.name}'
              : 'Request from ${req.name} declined'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final me = ref.watch(activePersonaProvider).valueOrNull;
    final requests = ref.watch(requestsProvider);
    final myHandle = me?.username ?? '';
    final myKalId = me?.kalId ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
          child: Text('Connect', style: AppTheme.display(size: 24, color: s.text)),
        ),

        // My QR card
        _Label('MY CODE'),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KColors.dPanel,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text('@$myHandle',
                  style: const TextStyle(
                      color: KColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: 'kalisi:@$myHandle',
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text('Friends type @$myHandle or scan this to connect.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 13)),
              const SizedBox(height: 4),
              Text('No phone number is exchanged — ever.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5), fontSize: 12)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _WhiteBtn(
                      label: 'Copy @username',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '@$myHandle'));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _WhiteBtn(
                      label: 'Copy ID',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: myKalId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('ID copied'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // Add a friend
        _Label('ADD A FRIEND'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _username,
                style: TextStyle(color: s.text),
                textCapitalization: TextCapitalization.none,
                onSubmitted: (_) => _addFriend(),
                decoration: InputDecoration(
                  prefixText: '@',
                  prefixStyle: TextStyle(color: s.muted, fontSize: 16),
                  hintText: 'username',
                  hintStyle: TextStyle(color: s.faint),
                  filled: true,
                  fillColor: s.panel,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
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
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [KColors.gold, KColors.ember]),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: _busy ? null : _addFriend,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.2, color: Colors.white))
                            : const Text('Send',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_msg!,
                style: TextStyle(
                    color: _msgOk ? KColors.ok : KColors.ember, fontSize: 13.5)),
          ),

        const SizedBox(height: 22),

        // Requests
        _Label('REQUESTS'),
        requests.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: KColors.gold))),
          ),
          error: (_, __) => Text('Could not load requests',
              style: TextStyle(color: s.muted)),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: s.panel,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: s.line),
                ),
                child: Text('No pending requests',
                    style: TextStyle(color: s.muted, fontSize: 14)),
              );
            }
            return Column(
              children: list.map((r) => _RequestRow(req: r, onAct: _act)).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  final IncomingRequest req;
  final Future<void> Function(IncomingRequest, bool) onAct;
  const _RequestRow({required this.req, required this.onAct});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: s.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(req.name,
                    style: TextStyle(
                        color: s.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                if (req.username != null)
                  Text('@${req.username}',
                      style: TextStyle(color: s.muted, fontSize: 13)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => onAct(req, false),
            child: Text('Decline', style: TextStyle(color: s.muted)),
          ),
          const SizedBox(width: 4),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [KColors.gold, KColors.ember]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onAct(req, true),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Accept',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
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

class _WhiteBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _WhiteBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: KColors.dBg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5)),
          ),
        ),
      ),
    );
  }
}
