import 'package:flutter/material.dart';
import '../theme/colors.dart';

class Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  const Avatar({
    super.key,
    required this.seed,
    required this.label,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final color = KColors.avatarFor(seed);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
