import 'package:flutter/material.dart';

/// Kalisi brand palette — matches the web app.
class KColors {
  // Brand
  static const gold = Color(0xFFF5A83C);
  static const goldDeep = Color(0xFFD98A1F);
  static const ember = Color(0xFFE4573F);
  static const ok = Color(0xFF59C98D);

  // Dark theme
  static const dBg = Color(0xFF0D1120);
  static const dPanel = Color(0xFF161C30);
  static const dPanel2 = Color(0xFF1E2540);
  static const dLine = Color(0xFF28304F);
  static const dText = Color(0xFFEDEEF4);
  static const dMuted = Color(0xFF8A91AB);
  static const dFaint = Color(0xFF5A6180);
  static const dMine = Color(0xFF2C3866);
  static const dTheirs = Color(0xFF1B2138);

  // Light theme
  static const lBg = Color(0xFFF4F5FA);
  static const lPanel = Color(0xFFFFFFFF);
  static const lPanel2 = Color(0xFFEEF0F7);
  static const lLine = Color(0xFFDDE1EC);
  static const lText = Color(0xFF141A2E);
  static const lMuted = Color(0xFF5A6178);
  static const lFaint = Color(0xFF9098AE);
  static const lMine = Color(0xFFD6E4FF);
  static const lTheirs = Color(0xFFFFFFFF);

  // Avatar palette (deterministic per contact)
  static const avatarColors = [
    Color(0xFFF5A83C),
    Color(0xFF7FA8F5),
    Color(0xFF59C98D),
    Color(0xFFE4739A),
    Color(0xFFB58CF0),
    Color(0xFF5FC9C9),
    Color(0xFFE4A05F),
  ];

  static Color avatarFor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatarColors[h % avatarColors.length];
  }
}

/// Semantic colors resolved from the current brightness.
class KScheme {
  final bool dark;
  const KScheme(this.dark);

  Color get bg => dark ? KColors.dBg : KColors.lBg;
  Color get panel => dark ? KColors.dPanel : KColors.lPanel;
  Color get panel2 => dark ? KColors.dPanel2 : KColors.lPanel2;
  Color get line => dark ? KColors.dLine : KColors.lLine;
  Color get text => dark ? KColors.dText : KColors.lText;
  Color get muted => dark ? KColors.dMuted : KColors.lMuted;
  Color get faint => dark ? KColors.dFaint : KColors.lFaint;
  Color get mine => dark ? KColors.dMine : KColors.lMine;
  Color get theirs => dark ? KColors.dTheirs : KColors.lTheirs;

  static KScheme of(BuildContext context) =>
      KScheme(Theme.of(context).brightness == Brightness.dark);
}
