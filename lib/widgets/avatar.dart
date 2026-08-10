import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Round profile photo (WhatsApp style) with a deterministic gradient.
class Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  const Avatar({
    super.key,
    required this.seed,
    required this.label,
    this.size = 55,
  });

  @override
  Widget build(BuildContext context) {
    final pair = KColors.avatarPairFor(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.37,
        ),
      ),
    );
  }
}
