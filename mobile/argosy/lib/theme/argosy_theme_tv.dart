import 'package:flutter/material.dart';

import 'argosy_theme.dart';

/// The TV (10-foot) theme: the same Argosy dark theme + brass palette, with the
/// type ramp scaled up for couch-distance legibility (ARGY-51). Built on top of
/// [buildArgosyTheme] so colors, component styles, and tokens stay identical —
/// only sizing differs. Per-screen layouts still set explicit sizes from the
/// 1920x1080 design where they need to; this just shifts the default baseline.
ThemeData buildArgosyThemeTv() {
  final base = buildArgosyTheme();
  return base.copyWith(textTheme: _scaleUp(base.textTheme, 1.3));
}

/// Scales every text style's size by [factor]. Done per-style (not via
/// [TextTheme.apply]'s `fontSizeFactor`, which asserts on any style that has a
/// null `fontSize`) so it's safe regardless of which styles carry a size.
TextTheme _scaleUp(TextTheme t, double factor) {
  TextStyle? up(TextStyle? s) => (s == null || s.fontSize == null)
      ? s
      : s.copyWith(fontSize: s.fontSize! * factor);
  return TextTheme(
    displayLarge: up(t.displayLarge),
    displayMedium: up(t.displayMedium),
    displaySmall: up(t.displaySmall),
    headlineLarge: up(t.headlineLarge),
    headlineMedium: up(t.headlineMedium),
    headlineSmall: up(t.headlineSmall),
    titleLarge: up(t.titleLarge),
    titleMedium: up(t.titleMedium),
    titleSmall: up(t.titleSmall),
    bodyLarge: up(t.bodyLarge),
    bodyMedium: up(t.bodyMedium),
    bodySmall: up(t.bodySmall),
    labelLarge: up(t.labelLarge),
    labelMedium: up(t.labelMedium),
    labelSmall: up(t.labelSmall),
  );
}
