import 'package:flutter/material.dart';

import 'argosy_colors.dart';
import 'argosy_tokens.dart';

/// Font families, as declared in `pubspec.yaml`.
const _display = 'Archivo'; // headings / numerals — the web's --arg-display
const _body = 'HankenGrotesk'; // running text — the web's --arg-body

/// Builds the single (dark) Argosy theme. Argosy is dark-only by design
/// (`color-scheme: dark` on the web), so there is no light variant.
ThemeData buildArgosyTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: ArgosyColors.accent,
    onPrimary: ArgosyColors.ink,
    primaryContainer: ArgosyColors.accentBg2,
    onPrimaryContainer: ArgosyColors.accentHi,
    secondary: ArgosyColors.accentSoft,
    onSecondary: ArgosyColors.ink,
    surface: ArgosyColors.bg,
    onSurface: ArgosyColors.cream,
    surfaceContainerLowest: ArgosyColors.ink,
    surfaceContainerLow: ArgosyColors.bg2,
    surfaceContainer: ArgosyColors.panel,
    surfaceContainerHigh: ArgosyColors.panel2,
    surfaceContainerHighest: ArgosyColors.panelHi,
    onSurfaceVariant: ArgosyColors.dim,
    outline: ArgosyColors.line2,
    outlineVariant: ArgosyColors.line,
    error: ArgosyColors.danger,
    onError: ArgosyColors.ink,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ArgosyColors.bg,
    canvasColor: ArgosyColors.bg,
    fontFamily: _body,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    extensions: const [ArgosyTokens.dark],
    textTheme: _buildTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: ArgosyColors.bg,
      foregroundColor: ArgosyColors.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _display,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ArgosyColors.cream,
        letterSpacing: 0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: ArgosyColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ArgosyTokens.dark.radiusLg),
        side: const BorderSide(color: ArgosyColors.line),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ArgosyColors.panel,
      selectedColor: ArgosyColors.accentBg2,
      side: const BorderSide(color: ArgosyColors.line2),
      labelStyle: const TextStyle(
        fontFamily: _body,
        fontSize: 13,
        color: ArgosyColors.soft2,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ArgosyColors.accent,
        foregroundColor: ArgosyColors.ink,
        disabledBackgroundColor: ArgosyColors.line2,
        textStyle: const TextStyle(
          fontFamily: _display,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ArgosyTokens.dark.radius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ArgosyColors.accentHi),
    ),
    dividerTheme: const DividerThemeData(
      color: ArgosyColors.line,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: ArgosyColors.soft2),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ArgosyColors.accent,
      linearTrackColor: ArgosyColors.line2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ArgosyColors.bg2,
      hintStyle: const TextStyle(color: ArgosyColors.faint),
      labelStyle: const TextStyle(color: ArgosyColors.dim),
      floatingLabelStyle: const TextStyle(color: ArgosyColors.accentHi),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ArgosyTokens.dark.radius),
        borderSide: const BorderSide(color: ArgosyColors.line2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ArgosyTokens.dark.radius),
        borderSide: const BorderSide(color: ArgosyColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ArgosyTokens.dark.radius),
        borderSide: const BorderSide(color: ArgosyColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ArgosyTokens.dark.radius),
        borderSide: const BorderSide(color: ArgosyColors.danger, width: 1.5),
      ),
    ),
  );
}

/// Display/headline styles use Archivo; titles, body and labels use Hanken
/// Grotesk. Colours default to the cream ink; dimmer shades come from
/// [ArgosyTokens].
TextTheme _buildTextTheme(TextTheme base) {
  TextStyle display(double size, FontWeight weight, {double spacing = 0}) =>
      TextStyle(
        fontFamily: _display,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: ArgosyColors.cream,
        height: 1.1,
      );

  TextStyle body(double size, FontWeight weight, {Color? color}) => TextStyle(
        fontFamily: _body,
        fontSize: size,
        fontWeight: weight,
        color: color ?? ArgosyColors.cream,
        height: 1.4,
      );

  return base.copyWith(
    displayLarge: display(40, FontWeight.w800, spacing: -0.5),
    displayMedium: display(32, FontWeight.w800, spacing: -0.3),
    displaySmall: display(26, FontWeight.w700),
    headlineMedium: display(22, FontWeight.w700),
    headlineSmall: display(19, FontWeight.w700),
    titleLarge: display(17, FontWeight.w600),
    titleMedium: body(15, FontWeight.w600),
    titleSmall: body(13, FontWeight.w600, color: ArgosyColors.soft2),
    bodyLarge: body(16, FontWeight.w400),
    bodyMedium: body(14, FontWeight.w400, color: ArgosyColors.soft2),
    bodySmall: body(12.5, FontWeight.w400, color: ArgosyColors.dim),
    labelLarge: body(14, FontWeight.w600),
    labelMedium: body(12, FontWeight.w500, color: ArgosyColors.dim),
    labelSmall: body(11, FontWeight.w500, color: ArgosyColors.faint),
  );
}
