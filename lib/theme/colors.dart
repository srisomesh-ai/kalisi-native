import 'package:flutter/material.dart';

/// Kalisi palette — BharatGPS colour family, WhatsApp-style layout.
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

  // Legacy aliases (older widgets still reference these)
  static const gold = amber;
  static const goldDeep = Color(0xFFD9720F);
  static const ember = Color(0xFFD9720F);
  static const ok = green;

  // Light
  static const lBg = Color(0xFFFFFFFF);        // list screens are white
  static const lChatBg = Color(0xFFEFF3F2);    // chat wallpaper
  static const lPanel = Color(0xFFFFFFFF);
  static const lPanel2 = Color(0xFFEFF3F2);    // search field
  static const lLine = Color(0xFFEDF1F0);
  static const lText = Color(0xFF16201F);
  static const lMuted = Color(0xFF55676A);
  static const lFaint = Color(0xFF8A9A98);
  static const lMine = Color(0xFFD9EDE9);      // my bubble (soft teal)
  static const lTheirs = Color(0xFFFFFFFF);

  // Dark
  static const dBg = Color(0xFF0D1817);
  static const dChatBg = Color(0xFF101E1D);
  static const dPanel = Color(0xFF152523);
  static const dPanel2 = Color(0xFF1C302E);
  static const dLine = Color(0xFF23403D);
  static const dText = Color(0xFFE9F1F0);
  static const dMuted = Color(0xFF95A9A7);
  static const dFaint = Color(0xFF6B807E);
  static const dMine = Color(0xFF14453F);
  static const dTheirs = Color(0xFF172A28);

  /// Profile-photo gradients (round avatars).
  static const avatarGradients = <List<Color>>[
    [Color(0xFF2FA0A0), Color(0xFF0E5C5C)],
    [Color(0xFFF5A623), Color(0xFFD9720F)],
    [Color(0xFF6C5CE7), Color(0xFF4B3FD1)],
    [Color(0xFF27AE60), Color(0xFF1B8449)],
    [Color(0xFF2E86DE), Color(0xFF1B62AC)],
    [Color(0xFFE4739A), Color(0xFFB03A63)],
  ];

  static List<Color> avatarFor(String seed) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return avatarGradients[h % avatarGradients.length];
  }
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
