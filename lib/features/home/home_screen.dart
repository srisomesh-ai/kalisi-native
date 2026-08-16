import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/push/push_service.dart';
import '../chats/chats_screen.dart';
import '../connect/connect_screen.dart';
import '../status/status_screen.dart';
import '../settings/settings_screen.dart';
import '../groups/new_group_screen.dart';
import '../call/call_screen.dart';
import '../../data/call/call_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // begin polling for incoming messages in the background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pollerProvider).start();
      final me = ref.read(activePersonaProvider).valueOrNull;
      if (me != null) {
        PushService.registerToken(ref.read(apiProvider), me.kalId, me.token);
      }

      // While the app is open, don't raise a banner for the chat already on
      // screen, or for a muted chat.
      PushService.suppress = (data) {
        final from = data['from']?.toString() ?? data['kal_id']?.toString();
        if (from == null) return false;
        final openId = ref.read(openChatIdProvider);
        if (openId == null) return false;
        final contact = ref.read(openChatKalIdProvider);
        return contact != null && contact == from;
      };
    });
  }

  bool _callScreenOpen = false;

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);

    // let other screens switch tabs
    ref.listen(goToTabProvider, (_, t) {
      if (t != null) {
        setState(() => _tab = t);
        ref.read(goToTabProvider.notifier).state = null;
      }
    });

    // An incoming call takes over the screen wherever we are.
    ref.listen(callServiceProvider, (_, call) {
      if (call.state == CallState.ringing && !_callScreenOpen) {
        _callScreenOpen = true;
        ref.read(pollerProvider).setFast(true);
        Navigator.of(context)
            .push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const CallScreen(),
            ))
            .then((_) {
          _callScreenOpen = false;
          ref.read(pollerProvider).setFast(false);
        });
      }
    });
    final pages = const [
      ChatsScreen(),
      StatusScreen(),
      ConnectScreen(),
      SettingsScreen(),
    ];

    return PopScope(
      // On Status/Connect/Privacy the back button returns to Chats.
      // Only on Chats does back leave the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) {
          setState(() => _tab = 0);
        }
      },
      child: Scaffold(
        body: SafeArea(bottom: false, child: pages[_tab]),
        floatingActionButton: (_tab == 0)
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FloatingActionButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const NewGroupScreen(),
                )),
                backgroundColor: KColors.teal,
                foregroundColor: Colors.white,
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(19)),
                child: const Icon(Icons.edit_rounded, size: 24),
              ),
            )
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: s.panel,
          border: Border(top: BorderSide(color: s.line)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -2),
            )
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chats',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0)),
              _NavItem(
                  icon: Icons.blur_circular_outlined,
                  label: 'Status',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1)),
              _NavItem(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Connect',
                  active: _tab == 2,
                  badge: ref.watch(requestsProvider).maybeWhen(
                        data: (r) => r.length,
                        orElse: () => 0,
                      ),
                  onTap: () => setState(() => _tab = 2)),
              _NavItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  active: _tab == 3,
                  onTap: () => setState(() => _tab = 3)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
                decoration: BoxDecoration(
                  color: active ? KColors.tealSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon,
                        color: active ? KColors.teal : s.muted, size: 23),
                    if (badge > 0)
                      Positioned(
                        top: -5,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 17),
                          decoration: BoxDecoration(
                            color: KColors.amber,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: s.panel, width: 1.5),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: active ? s.text : s.muted,
                      fontSize: 12.5,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
