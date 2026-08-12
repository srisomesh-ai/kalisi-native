import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/call/call_service.dart';
import '../../widgets/avatar.dart';

/// Full-screen call UI.
///
/// Kept in its own file so the look can be reworked without touching the
/// call logic in data/call/call_service.dart.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});
  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  bool _closing = false;

  @override
  void dispose() {
    _pulse.dispose();
    _enter.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callServiceProvider);
    final peer = call.peer;

    // close once the call is over — guarded so it only happens once
    if (call.state == CallState.ended && !_closing) {
      _closing = true;
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          Navigator.of(context).maybePop();
          ref.read(callServiceProvider).reset();
        }
      });
    }

    final label = switch (call.state) {
      CallState.calling => 'Calling…',
      CallState.ringing => 'Incoming call',
      CallState.connecting => 'Connecting…',
      CallState.connected => call.onHold ? 'On hold' : _fmt(call.duration),
      CallState.ended => call.error ?? 'Call ended',
      CallState.idle => '',
    };

    final ringing = call.state == CallState.calling ||
        call.state == CallState.ringing ||
        call.state == CallState.connecting;

    return PopScope(
      canPop: !call.isActive,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E5C5C), Color(0xFF0A3F45), Color(0xFF07272C)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 18),
                _EncryptedPill(),
                const Spacer(flex: 2),

                // avatar, pulsing softly while ringing
                FadeTransition(
                  opacity: _enter,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.86, end: 1.0).animate(
                      CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
                    ),
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, child) {
                        final t = ringing ? _pulse.value : 0.0;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            if (ringing) ...[
                              _Halo(scale: 1.0 + t * 0.28, opacity: 0.16 * (1 - t)),
                              _Halo(scale: 1.0 + t * 0.16, opacity: 0.22 * (1 - t)),
                            ],
                            child!,
                          ],
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.35),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Avatar(
                          seed: peer?.kalId ?? 'x',
                          label: (peer?.name.isNotEmpty ?? false)
                              ? peer!.name[0].toUpperCase()
                              : '?',
                          size: 148,
                          photo: peer?.avatar,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _enter,
                  child: Column(
                    children: [
                      Text(
                        peer?.name ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4),
                      ),
                      const SizedBox(height: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          label,
                          key: ValueKey(label),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.82),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [],
                            ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                if (call.state == CallState.ringing)
                  _IncomingControls(call: call)
                else
                  _ActiveControls(call: call, enter: _enter),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft expanding ring behind the avatar while the call is ringing.
class _Halo extends StatelessWidget {
  final double scale;
  final double opacity;
  const _Halo({required this.scale, required this.opacity});
  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 148,
        height: 148,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(opacity),
        ),
      ),
    );
  }
}

class _EncryptedPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, size: 12, color: Colors.white70),
          const SizedBox(width: 6),
          Text('end-to-end encrypted',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  final CallService call;
  const _IncomingControls({required this.call});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _BigBtn(
            icon: Icons.call_end_rounded,
            color: KColors.danger,
            label: 'Decline',
            onTap: call.decline,
          ),
          _BigBtn(
            icon: Icons.call_rounded,
            color: const Color(0xFF27AE60),
            label: 'Accept',
            onTap: call.accept,
            bounce: true,
          ),
        ],
      ),
    );
  }
}

class _ActiveControls extends ConsumerWidget {
  final CallService call;
  final Animation<double> enter;
  const _ActiveControls({required this.call, required this.enter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = call.state == CallState.connected;
    return FadeTransition(
      opacity: enter,
      child: Column(
        children: [
          // row 1
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallBtn(
                icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                on: call.muted,
                label: 'Mute',
                onTap: call.toggleMute,
              ),
              const SizedBox(width: 22),
              _SmallBtn(
                icon: call.speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.hearing_rounded,
                on: call.speakerOn,
                label: 'Speaker',
                onTap: call.toggleSpeaker,
              ),
              const SizedBox(width: 22),
              _SmallBtn(
                icon: Icons.bluetooth_audio_rounded,
                on: call.bluetoothOn,
                label: 'Bluetooth',
                onTap: call.toggleBluetooth,
              ),
            ],
          ),
          const SizedBox(height: 18),
          // row 2
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallBtn(
                icon: call.onHold
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                on: call.onHold,
                label: call.onHold ? 'Resume' : 'Hold',
                enabled: live,
                onTap: call.toggleHold,
              ),
              const SizedBox(width: 22),
              _SmallBtn(
                icon: Icons.person_add_alt_1_rounded,
                on: false,
                label: 'Add',
                enabled: live,
                onTap: () => _addPersonNotice(context),
              ),
              const SizedBox(width: 22),
              _SmallBtn(
                icon: Icons.chat_bubble_outline_rounded,
                on: false,
                label: 'Message',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _BigBtn(
            icon: Icons.call_end_rounded,
            color: KColors.danger,
            label: 'End',
            onTap: () => call.hangUp(),
          ),
        ],
      ),
    );
  }

  void _addPersonNotice(BuildContext context) {
    final s = KScheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: s.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_rounded, color: KColors.teal),
                  const SizedBox(width: 10),
                  Text('Add someone to this call',
                      style: TextStyle(
                          color: s.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  'Three-way calling needs a media server to mix the audio — a direct phone-to-phone call can only carry two people. It is the next piece of work on calling.',
                  style:
                      TextStyle(color: s.muted, fontSize: 13.5, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool bounce;
  const _BigBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.bounce = false,
  });

  @override
  State<_BigBtn> createState() => _BigBtnState();
}

class _BigBtnState extends State<_BigBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.bounce) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, widget.bounce ? -5 * _c.value : 0),
            child: child,
          ),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.5),
                    blurRadius: 22,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(widget.icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(widget.label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _SmallBtn({
    required this.icon,
    required this.on,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final dim = !enabled;
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: enabled ? onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.white.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(on ? 0 : 0.18),
                ),
              ),
              child: Icon(icon,
                  color: on ? KColors.teal : Colors.white, size: 25),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
