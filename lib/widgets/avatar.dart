import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Round profile photo with a deterministic gradient, WhatsApp-style.
class Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  final bool ring;          // amber ring (unseen status)
  final bool ringSeen;      // grey ring (already viewed)

  const Avatar({
    super.key,
    required this.seed,
    required this.label,
    this.size = 52,
    this.ring = false,
    this.ringSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    final pair = KColors.avatarPairFor(seed);
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: pair,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.38,
        ),
      ),
    );

    if (!ring && !ringSeen) return inner;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring
            ? const LinearGradient(colors: [KColors.amber, Color(0xFFFFD79A)])
            : null,
        color: ringSeen ? const Color(0x66FFFFFF) : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: inner,
      ),
    );
  }
}
