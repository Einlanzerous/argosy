import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// Lays a TV screen out in a fixed **1920×1080 design space** and scales it to
/// fit the actual display (ARGY-51).
///
/// TVs hand Flutter a logical viewport that's often far smaller than 1920×1080
/// (e.g. a Chromecast reports ~960×540 at 2× density), so fixed pixel sizes come
/// out oversized and overflow the screen. Authoring every TV screen at the
/// design's native 1920×1080 and `BoxFit.contain`-scaling it means the layout is
/// pixel-accurate to the Claude Design comps and always fits, on any TV. Both
/// 1920×1080 and a 16:9 panel share the same aspect ratio, so there's no
/// letterboxing.
class TvStage extends StatelessWidget {
  const TvStage({super.key, required this.child, this.background});

  static const double designWidth = 1920;
  static const double designHeight = 1080;

  final Widget child;

  /// Fill behind the scaled canvas. Defaults to the app background; pass
  /// [Colors.transparent] when the stage scales a *transparent* layer over
  /// something else (e.g. the player's control overlay above the video — an
  /// opaque fill there would hide the video while audio kept playing).
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background ?? ArgosyColors.bg,
      child: Center(
        child: FittedBox(
          child: SizedBox(
            width: designWidth,
            height: designHeight,
            child: child,
          ),
        ),
      ),
    );
  }
}
