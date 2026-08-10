import 'package:flutter/material.dart';

/// Kalisi palette — matches the HamaraService / BharatGPS Flutter apps:
/// teal headers/nav + warm-orange actions on a soft blue-green background.
class KColors {
  // Brand (warm orange = primary action; kept names gold/ember for compatibility)
  static const gold = Color(0xFFE8651A);      // warm orange (primary action)
  static const goldDeep = Color(0xFFC9510F);
  static const ember = Color(0xFFC9510F);     // deeper orange (gradient end)
  static const ok = Color(0xFF2ECC71);        // green (online / success)

  // Teal (headers, nav, accents)
  static const teal = Color(0xFF1B6B7A);
  static const teal2 = Color(0xFF134F5C);
  static const tealSoft = Color(0xFFE6F4F6);

  // Dark theme (teal-tinted dark)
  static const dBg = Color(0xFF0E1A1D);
  static const dPanel = Color(0xFF14262B);
  static const dPanel2 = Color(0xFF1B3238);
  static const dLine = Color(0xFF244047);
  static const dText = Color(0xFFEAF2F3);
  static const dMuted = Color(0xFF8FA6AB);
  static const dFaint = Color(0xFF5E767C);
  static const dMine = Color(0xFF1F4A52);      // teal bubble (mine)
  static const dTheirs = Color(0xFF17292E);

  // Light theme (HamaraService)
  static const lBg = Color(0xFFF0F7F9);        // soft blue-green
  static const lPanel = Color(0xFFFFFFFF);
  static const lPanel2 = Color(0xFFE9F1F3);
  static const lLine = Color(0xFFE2E8F0);
  static const lText = Color(0xFF1A1A2E);
  static const lMuted = Color(0xFF718096);
  static const lFaint = Color(0xFF9AA8AE);
  static const lMine = Color(0xFFDFF1F4);      // soft teal bubble (mine)
  static const lTheirs = Color(0xFFFFFFFF);

  // Avatar palette (warm + teal mix, matches the apps)
  static const avatarColors = [
    Color(0xFFE8651A),
    Color(0xFF1B6B7A),
    Color(0xFF2ECC71),
    Color(0xFF6C5CE7),
    Color(0xFFF39C12),
    Color(0xFF2E86DE),
    Color(0xFFE4739A),
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
