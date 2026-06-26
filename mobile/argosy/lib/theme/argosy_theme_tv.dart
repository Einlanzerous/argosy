import 'package:flutter/material.dart';

import 'argosy_theme.dart';

/// The TV (10-foot) theme: the same Argosy dark theme + brass palette, with the
/// type ramp scaled up for couch-distance legibility (ARGY-51). Built on top of
/// [buildArgosyTheme] so colors, component styles, and tokens stay identical —
/// only sizing differs. Per-screen layouts still set explicit sizes from the
/// 1920x1080 design where they need to; this just shifts the default baseline.
ThemeData buildArgosyThemeTv() {
  final base = buildArgosyTheme();
  return base.copyWith(
    textTheme: base.textTheme.apply(fontSizeFactor: 1.3),
  );
}
