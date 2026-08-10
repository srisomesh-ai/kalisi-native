import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Round profile photo with a deterministic gradient, WhatsApp-style.
class Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  final bool ring;          // unseen-status ring
  final bool ringSeen;

  const Avatar({
    super.key,
    required this.seed,
    required this.label,
    this.size = 48,
    this.ring = false,
    this.ringSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = KColors.avatarFor(seed);
    final photo = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: g,
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

    if (!ring) return photo;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringSeen ? Colors.white.withOpacity(0.45) : null,
        gradient: ringSeen
            ? null
            : const LinearGradient(
                colors: [KColors.amber, Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: photo,
    );
  }
}
