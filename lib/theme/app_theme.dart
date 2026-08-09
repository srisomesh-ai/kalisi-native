import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData light() => _build(false);
  static ThemeData dark() => _build(true);

  static ThemeData _build(bool dark) {
    final s = KScheme(dark);
    final base = dark ? ThemeData.dark() : ThemeData.light();
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: s.text,
      displayColor: s.text,
    );

    return base.copyWith(
      scaffoldBackgroundColor: s.bg,
      canvasColor: s.bg,
      primaryColor: KColors.gold,
      textTheme: textTheme,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: KColors.gold,
        secondary: KColors.ember,
        surface: s.panel,
        error: KColors.ember,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: s.text,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: s.text,
          letterSpacing: -0.3,
        ),
      ),
      dividerColor: s.line,
      iconTheme: IconThemeData(color: s.muted),
      splashColor: KColors.gold.withOpacity(0.08),
      highlightColor: KColors.gold.withOpacity(0.05),
    );
  }

  /// Display font for big headings (matches the web's Bricolage Grotesque).
  static TextStyle display({
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w800,
    double spacing = -0.01,
  }) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );
}
