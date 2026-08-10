import 'package:flutter/material.dart';

/// Kalisi palette — BharatGPS colours in a WhatsApp-style layout.
class KColors {
  // Brand
  static const teal = Color(0xFF0E5C5C);
  static const teal2 = Color(0xFF137272);
  static const tealSoft = Color(0xFFDFEDEC);

  // Accent
  static const amber = Color(0xFFF5A623);
  static const amberBg = Color(0xFFFDF1DE);
  static const amberInk = Color(0xFFC77F0C);

  // Semantic
  static const green = Color(0xFF27AE60);
  static const greenBg = Color(0xFFE7F7EC);
  static const red = Color(0xFFE74C3C);
  static const redBg = Color(0xFFFCEAE8);
  static const violet = Color(0xFF6C5CE7);
  static const blue = Color(0xFF2E86DE);

  /// Legacy aliases (older widgets still reference these).
  static const gold = teal;
  static const goldDeep = teal2;
  static const ember = amber;
  static const ok = green;

  // Light
  static const lBg = Color(0xFFFFFFFF);       // list screens are white
  static const lChatBg = Color(0xFFEFF3F2);   // chat wallpaper
  static const lPanel = Color(0xFFFFFFFF);
  static const lPanel2 = Color(0xFFEFF3F2);   // search field
  static const lLine = Color(0xFFEDF1F0);
  static const lText = Color(0xFF16201F);
  static const lMuted = Color(0xFF55676A);
  static const lFaint = Color(0xFF8A9A98);
  static const lMine = Color(0xFFD9EDE9);     // my bubble (soft teal)
  static const lTheirs = Color(0xFFFFFFFF);

  // Dark
  static const dBg = Color(0xFF0E1A1A);
  static const dChatBg = Color(0xFF0B1614);
  static const dPanel = Color(0xFF152524);
  static const dPanel2 = Color(0xFF1D3230);
  static const dLine = Color(0xFF24403E);
  static const dText = Color(0xFFEAF2F1);
  static const dMuted = Color(0xFF9AAFAD);
  static const dFaint = Color(0xFF6B807E);
  static const dMine = Color(0xFF1E4A46);
  static const dTheirs = Color(0xFF162927);

  /// Avatar gradients (round photos in the list).
  static const avatarPairs = <List<Color>>[
    [Color(0xFF2FA0A0), Color(0xFF0E5C5C)],
    [Color(0xFFF5A623), Color(0xFFD9720F)],
    [Color(0xFF6C5CE7), Color(0xFF3F32B0)],
    [Color(0xFF27AE60), Color(0xFF1B8449)],
    [Color(0xFF2E86DE), Color(0xFF1B62AC)],
    [Color(0xFFE4739A), Color(0xFFB03A63)],
  ];

  static List<Color> avatarPairFor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatarPairs[h % avatarPairs.length];
  }

  static Color avatarFor(String seed) => avatarPairFor(seed).last;
}

class KScheme {
  final bool dark;
  const KScheme(this.dark);

  Color get bg => dark ? KColors.dBg : KColors.lBg;
  Color get chatBg => dark ? KColors.dChatBg : KColors.lChatBg;
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
