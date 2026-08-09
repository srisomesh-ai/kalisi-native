import 'package:flutter/material.dart';
import '../theme/colors.dart';

class KButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool ghost;
  const KButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.ghost = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    if (ghost) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: s.text,
            side: BorderSide(color: s.line),
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13)),
          ),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: onPressed == null
              ? null
              : const LinearGradient(colors: [KColors.gold, KColors.ember]),
          color: onPressed == null ? s.panel2 : null,
          borderRadius: BorderRadius.circular(13),
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: KColors.ember.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
