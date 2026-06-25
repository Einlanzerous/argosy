import 'package:flutter/material.dart';

// Charcoal/teal/brown gradient placeholders — a port of the web client's
// `gradientFor` (`web/src/lib/poster.ts`), kept in sync so a given title draws
// the same placeholder on both surfaces when it has no cached artwork.
const _gradients = <List<Color>>[
  [Color(0xFF26323F), Color(0xFF12171C)],
  [Color(0xFF3A2A28), Color(0xFF171110)],
  [Color(0xFF1F342F), Color(0xFF0F1614)],
  [Color(0xFF2B2F38), Color(0xFF13151A)],
  [Color(0xFF332439), Color(0xFF161018)],
  [Color(0xFF24333A), Color(0xFF101618)],
  [Color(0xFF34301F), Color(0xFF171510)],
  [Color(0xFF21332B), Color(0xFF0F1614)],
];

int _hash(String seed) {
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

/// A deterministic placeholder gradient for [seed], matching the web's 158°
/// charcoal-to-near-black ramp (begin top-right → end bottom-left approximates
/// the CSS angle closely enough at thumbnail size).
LinearGradient posterGradient(String seed) {
  final colors = _gradients[_hash(seed) % _gradients.length];
  return LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: colors,
  );
}
