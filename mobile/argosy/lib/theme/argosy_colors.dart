import 'package:flutter/widgets.dart';

/// The Argosy palette — brass-on-charcoal, mercantile. These are a direct
/// port of the web design tokens in `web/src/style.css` (`--arg-*`), kept in
/// sync so the mobile client reads as the same product.
abstract final class ArgosyColors {
  // Surfaces (darkest → lightest), charcoal.
  static const bg = Color(0xFF171717); // --arg-bg
  static const bg2 = Color(0xFF141413); // --arg-bg-2
  static const panel = Color(0xFF1C1C1A); // --arg-panel
  static const panel2 = Color(0xFF1D1D1B); // --arg-panel-2
  static const panelHi = Color(0xFF201F1C); // --arg-panel-hi
  static const ink = Color(0xFF0C0C0B); // --arg-ink
  static const ink2 = Color(0xFF121211); // --arg-ink-2

  // Foreground text ramp (brightest → faintest).
  static const cream = Color(0xFFEAEAE5); // --arg-cream (primary text)
  static const soft = Color(0xFFB8B8B0); // --arg-soft
  static const soft2 = Color(0xFFCFCFC7); // --arg-soft-2
  static const dim = Color(0xFF9A9A92); // --arg-dim (secondary text)
  static const faint = Color(0xFF6F6F68); // --arg-faint
  static const faint2 = Color(0xFF5F5F58); // --arg-faint-2
  static const mute = Color(0xFF7A7A72); // --arg-mute

  // Accents.
  static const accent = Color(0xFFC99A4E); // --arg-accent (brass)
  static const accentHi = Color(0xFFDDB066); // --arg-accent-hi
  static const accentSoft = Color(0xFFD9B87F); // --arg-accent-soft
  static const green = Color(0xFF5AA86A); // --arg-green (success/progress)
  static const danger = Color(0xFFE08A6E); // --arg-danger

  // Hairlines & accent washes (alpha over cream/accent).
  static const line = Color(0x14EAEAE5); // --arg-line  (0.08)
  static const line2 = Color(0x24EAEAE5); // --arg-line-2 (0.14)
  static const line3 = Color(0x2EEAEAE5); // --arg-line-3 (0.18)
  static const accentLine = Color(0x38C99A4E); // --arg-accent-line (0.22)
  static const accentBg = Color(0x1AC99A4E); // --arg-accent-bg  (0.10)
  static const accentBg2 = Color(0x29C99A4E); // --arg-accent-bg-2 (0.16)
}
