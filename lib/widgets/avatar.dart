import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Round profile photo. Shows the real picture when one is set,
/// otherwise a deterministic gradient with the initial.
class Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  final String? photo; // base64 data URL
  const Avatar({
    super.key,
    required this.seed,
    required this.label,
    this.size = 55,
    this.photo,
  });

  static Uint8List? decode(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      final i = dataUrl.indexOf(',');
      return base64Decode(i >= 0 ? dataUrl.substring(i + 1) : dataUrl);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decode(photo);
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
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
