import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/colors.dart';

/// Splash with a padlock that springs open, shown only when the app has been
/// away for a while — coming straight back from a call or a message goes
/// directly to the chats.
class SplashGate extends StatefulWidget {
  final Widget child;
  const SplashGate({super.key, required this.child});

  /// How long the app must have been closed before the splash plays again.
  static const idleBeforeSplash = Duration(minutes: 30);
  static const _key = 'last_seen_ms';

  /// Remember when the app was last used.
  static Future<void> markSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Has it been long enough to show the splash again?
  static Future<bool> shouldShow() async {
    try {
      final p = await SharedPreferences.getInstance();
      final last = p.getInt(_key);
      if (last == null) return true; // first ever launch
      final gap = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(last));
      return gap >= idleBeforeSplash;
    } catch (_) {
      return false;
    }
  }

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> with WidgetsBindingObserver {
  bool? _show; // null while we're deciding

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _decide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // note when we go away, so the next launch can measure the gap
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      SplashGate.markSeen();
    }
  }

  Future<void> _decide() async {
    final show = await SplashGate.shouldShow();
    await SplashGate.markSeen();
    if (mounted) setState(() => _show = show);
  }

  @override
  Widget build(BuildContext context) {
    if (_show == null) {
      // brief blank in the app's own colour, not a white flash
      return const ColoredBox(color: KColors.teal, child: SizedBox.expand());
    }
    if (_show == false) return widget.child;
    return UnlockSplash(
      onDone: () => setState(() => _show = false),
      child: widget.child,
    );
  }
}

/// The animation itself: a padlock springs open, the name fades in,
/// then the whole panel zooms away to reveal the app.
class UnlockSplash extends StatefulWidget {
  final Widget child;
  final VoidCallback onDone;
  const UnlockSplash({super.key, required this.child, required this.onDone});

  @override
  State<UnlockSplash> createState() => _UnlockSplashState();
}

class _UnlockSplashState extends State<UnlockSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  // 0.00–0.22  settle
  // 0.22–0.50  shackle springs open
  // 0.40–0.65  name fades up
  // 0.68–1.00  panel zooms away
  late final Animation<double> _shackle = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.22, 0.50, curve: Curves.easeOutBack),
  );
  late final Animation<double> _name = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.40, 0.65, curve: Curves.easeOut),
  );
  late final Animation<double> _exit = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.68, 1.0, curve: Curves.easeInCubic),
  );
  late final Animation<double> _lockIn = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.28, curve: Curves.easeOutBack),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // the app, already there behind the panel
        widget.child,

        AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            if (_exit.value >= 1) return const SizedBox.shrink();
            return Opacity(
              opacity: (1 - _exit.value).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1 + _exit.value * 0.6,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        KColors.teal,
                        Color(0xFF0A3F45),
                        Color(0xFF07272C),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.6 + _lockIn.value * 0.4,
                          child: Opacity(
                            opacity: _lockIn.value.clamp(0.0, 1.0),
                            child: _Padlock(open: _shackle.value),
                          ),
                        ),
                        const SizedBox(height: 26),
                        Opacity(
                          opacity: _name.value.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - _name.value)),
                            child: const Text(
                              'Kalisi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Opacity(
                          opacity: (_name.value * 0.75).clamp(0.0, 1.0),
                          child: const Text(
                            'private by design',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The Kalisi mark: an envelope whose flap opens as [open] goes 0 → 1.
class _Padlock extends StatelessWidget {
  final double open;
  const _Padlock({required this.open});

  @override
  Widget build(BuildContext context) {
    final t = open.clamp(0.0, 1.0);
    return SizedBox(
      width: 168,
      height: 116,
      child: CustomPaint(painter: _MarkPainter(open: t)),
    );
  }
}

/// Draws the envelope body, the K, and the amber flap swinging open.
class _MarkPainter extends CustomPainter {
  final double open;
  _MarkPainter({required this.open});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bodyW = w * 0.74;

    // envelope body
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, bodyW, h),
      const Radius.circular(14),
    );
    canvas.drawRRect(body, Paint()..color = Colors.white);

    // flap — swings out to the right as it opens
    canvas.save();
    canvas.translate(bodyW, h / 2);
    canvas.scale(0.55 + 0.45 * open, 1.0);
    final flap = Path()
      ..moveTo(0, -h / 2)
      ..lineTo(w - bodyW, 0)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(
      flap,
      Paint()
        ..shader = const LinearGradient(
          colors: [KColors.amber, Color(0xFFD9720F)],
        ).createShader(Rect.fromLTWH(0, -h / 2, w - bodyW, h)),
    );
    canvas.restore();

    // the K
    final k = Paint()
      ..color = KColors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final left = bodyW * 0.28;
    final top = h * 0.24;
    final bottom = h * 0.76;
    final mid = h / 2;
    final armX = bodyW * 0.66;

    canvas.drawLine(Offset(left, top), Offset(left, bottom), k);
    final arms = Path()
      ..moveTo(armX, top)
      ..lineTo(left + 9, mid)
      ..lineTo(armX, bottom);
    canvas.drawPath(arms, k);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.open != open;
}
