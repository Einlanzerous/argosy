import 'package:flutter/material.dart';

import 'argosy_colors.dart';

/// Argosy design tokens that don't map cleanly onto Material's [ColorScheme] —
/// the text ramp, hairlines, accent washes, and the corner-radius scale.
/// Pull them off the theme: `Theme.of(context).extension<ArgosyTokens>()!`,
/// or the [BuildContext.argosy] shortcut below.
@immutable
class ArgosyTokens extends ThemeExtension<ArgosyTokens> {
  const ArgosyTokens({
    required this.softInk,
    required this.dimInk,
    required this.faintInk,
    required this.accentHi,
    required this.progress,
    required this.line,
    required this.line2,
    required this.accentLine,
    required this.accentWash,
    required this.radiusSm,
    required this.radius,
    required this.radiusLg,
    required this.radiusXl,
  });

  /// Secondary / tertiary text shades (brightest → faintest).
  final Color softInk;
  final Color dimInk;
  final Color faintInk;

  /// Brighter accent for hover/active emphasis.
  final Color accentHi;

  /// Watch-progress / success green.
  final Color progress;

  /// Hairline borders.
  final Color line;
  final Color line2;

  /// Accent-tinted border and fill for selected/active surfaces.
  final Color accentLine;
  final Color accentWash;

  /// Corner-radius scale (mirrors `--arg-r-*`).
  final double radiusSm;
  final double radius;
  final double radiusLg;
  final double radiusXl;

  static const dark = ArgosyTokens(
    softInk: ArgosyColors.soft,
    dimInk: ArgosyColors.dim,
    faintInk: ArgosyColors.faint,
    accentHi: ArgosyColors.accentHi,
    progress: ArgosyColors.green,
    line: ArgosyColors.line,
    line2: ArgosyColors.line2,
    accentLine: ArgosyColors.accentLine,
    accentWash: ArgosyColors.accentBg,
    radiusSm: 8,
    radius: 10,
    radiusLg: 12,
    radiusXl: 16,
  );

  @override
  ArgosyTokens copyWith({
    Color? softInk,
    Color? dimInk,
    Color? faintInk,
    Color? accentHi,
    Color? progress,
    Color? line,
    Color? line2,
    Color? accentLine,
    Color? accentWash,
    double? radiusSm,
    double? radius,
    double? radiusLg,
    double? radiusXl,
  }) {
    return ArgosyTokens(
      softInk: softInk ?? this.softInk,
      dimInk: dimInk ?? this.dimInk,
      faintInk: faintInk ?? this.faintInk,
      accentHi: accentHi ?? this.accentHi,
      progress: progress ?? this.progress,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      accentLine: accentLine ?? this.accentLine,
      accentWash: accentWash ?? this.accentWash,
      radiusSm: radiusSm ?? this.radiusSm,
      radius: radius ?? this.radius,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
    );
  }

  @override
  ArgosyTokens lerp(ArgosyTokens? other, double t) {
    if (other == null) return this;
    return ArgosyTokens(
      softInk: Color.lerp(softInk, other.softInk, t)!,
      dimInk: Color.lerp(dimInk, other.dimInk, t)!,
      faintInk: Color.lerp(faintInk, other.faintInk, t)!,
      accentHi: Color.lerp(accentHi, other.accentHi, t)!,
      progress: Color.lerp(progress, other.progress, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t),
      radius: lerpDouble(radius, other.radius, t),
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t),
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Ergonomic access to Argosy tokens from any [BuildContext].
extension ArgosyThemeX on BuildContext {
  ArgosyTokens get argosy => Theme.of(this).extension<ArgosyTokens>()!;
}
