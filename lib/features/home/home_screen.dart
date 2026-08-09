import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../chats/chats_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final pages = const [
      ChatsScreen(),
      _Placeholder(title: 'Status'),
      _Placeholder(title: 'Connect'),
      _Placeholder(title: 'Privacy'),
    ];

    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_tab]),
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
                  onTap: () => setState(() => _tab = 2)),
              _NavItem(
                  icon: Icons.shield_outlined,
                  label: 'Privacy',
                  active: _tab == 3,
                  onTap: () => setState(() => _tab = 3)),
            ],
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
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    final color = active ? KColors.gold : s.faint;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: active ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Icon(icon, color: color, size: 25),
              ),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});
  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Center(
      child: Text('$title — coming next',
          style: TextStyle(color: s.muted, fontSize: 16)),
    );
  }
}
