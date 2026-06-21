import 'package:flutter/material.dart';

/// The Argosy ship mark (logo-only, no wordmark). The app is dark-only, so this
/// renders the light/silver mark intended for dark surfaces.
class ArgosyMark extends StatelessWidget {
  const ArgosyMark({super.key, this.size = 96});

  static const _asset = 'assets/brand/argosy_mark_light.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
