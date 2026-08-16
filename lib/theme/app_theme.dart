import 'package:flutter/material.dart';
import 'colors.dart';

/// Theme using the device's built-in font (Roboto on Android).
/// No runtime font downloads — text always renders, even offline.
class AppTheme {
  static ThemeData light() => _build(false);
  static ThemeData dark() => _build(true);

  static ThemeData _build(bool dark) {
    final s = KScheme(dark);
    final base = dark ? ThemeData.dark() : ThemeData.light();
    final textTheme = base.textTheme.apply(
      bodyColor: s.text,
      displayColor: s.text,
    );

    return base.copyWith(
      scaffoldBackgroundColor: s.bg,
      canvasColor: s.bg,
      primaryColor: KColors.teal,
      textTheme: textTheme,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: KColors.teal,
        secondary: KColors.amber,
        surface: s.panel,
        error: KColors.danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.panel,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: s.text,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: s.text,
          letterSpacing: -0.3,
        ),
      ),
      // Painted behind everything, so a keyboard resize or a page change
      // never flashes the default white through.
      dialogBackgroundColor: s.panel,
      // Smooth, consistent page transitions on every Android version
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerColor: s.line,
      iconTheme: IconThemeData(color: s.muted),
      splashColor: KColors.teal.withOpacity(0.08),
      highlightColor: KColors.teal.withOpacity(0.05),
    );
  }

  /// Big heading style (system font, heavy weight).
  static TextStyle display({
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w800,
    double spacing = -0.4,
  }) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
      );
}
