import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../data/call/call_service.dart';
import '../../widgets/avatar.dart';

/// Full-screen call UI — ringing, connecting, in-call.
class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callServiceProvider);
    final peer = call.peer;

    // call finished — close after a beat
    if (call.state == CallState.ended) {
      Future.delayed(const Duration(milliseconds: 900), () {
        if (context.mounted) {
          Navigator.of(context).maybePop();
          ref.read(callServiceProvider).reset();
        }
      });
    }

    final label = switch (call.state) {
      CallState.calling => 'Calling…',
      CallState.ringing => 'Incoming call',
      CallState.connecting => 'Connecting…',
      CallState.connected => _fmt(call.duration),
      CallState.ended => call.error ?? 'Call ended',
      CallState.idle => '',
    };

    return PopScope(
      canPop: !call.isActive,
      child: Scaffold(
        backgroundColor: KColors.teal,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Avatar(
                seed: peer?.kalId ?? 'x',
                label: (peer?.name.isNotEmpty ?? false)
                    ? peer!.name[0].toUpperCase()
                    : '?',
                size: 132,
                photo: peer?.avatar,
              ),
              const SizedBox(height: 22),
              Text(
                peer?.name ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (call.state == CallState.connected)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.lock, size: 13, color: Colors.white70),
                    ),
                  Text(
                    label,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 15,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (call.state == CallState.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('end-to-end encrypted',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.5), fontSize: 12)),
                ),
              const Spacer(flex: 3),

              // controls
              if (call.state == CallState.ringing)
                _IncomingControls(call: call)
              else
                _ActiveControls(call: call),

              const SizedBox(height: 34),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  final CallService call;
  const _IncomingControls({required this.call});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundBtn(
          icon: Icons.call_end_rounded,
          color: KColors.danger,
          label: 'Decline',
          onTap: () => call.decline(),
        ),
        _RoundBtn(
          icon: Icons.call_rounded,
          color: const Color(0xFF27AE60),
          label: 'Accept',
          onTap: () => call.accept(),
        ),
      ],
    );
  }
}

class _ActiveControls extends StatelessWidget {
  final CallService call;
  const _ActiveControls({required this.call});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SmallBtn(
              icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              on: call.muted,
              label: 'Mute',
              onTap: call.toggleMute,
            ),
            const SizedBox(width: 34),
            _SmallBtn(
              icon: call.speakerOn
                  ? Icons.volume_up_rounded
                  : Icons.hearing_rounded,
              on: call.speakerOn,
              label: 'Speaker',
              onTap: call.toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: 30),
        _RoundBtn(
          icon: Icons.call_end_rounded,
          color: KColors.danger,
          label: 'End',
          onTap: () => call.hangUp(),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 31),
          ),
        ),
        const SizedBox(height: 9),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.8), fontSize: 13)),
      ],
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String label;
  final VoidCallback onTap;
  const _SmallBtn({
    required this.icon,
    required this.on,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                color: on ? KColors.teal : Colors.white, size: 25),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(
                color: Colors.white.withOpacity(0.75), fontSize: 12)),
      ],
    );
  }
}
