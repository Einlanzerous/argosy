import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// A secondary action drawn three ways, same action each time:
///  - a 44dp icon circle (compact season header; label is the tooltip),
///  - a 50dp rounded square (the show-level row beside Resume), or
///  - a labelled 40dp pill (expanded season header).
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconOnly = false,
    this.square = false,
    this.iconColor,
    this.leading,
    this.shortLabel,
  });

  /// Glyph, ignored when [leading] is given (e.g. a progress ring).
  final IconData icon;

  /// Tooltip / semantics label, and the pill text unless [shortLabel] is set.
  final String label;
  final VoidCallback? onPressed;

  /// Icon circle (44dp) instead of a labelled pill.
  final bool iconOnly;

  /// 50dp rounded square (radius 12) instead of a circle; implies icon-only.
  final bool square;
  final Color? iconColor;

  /// A custom leading widget in place of [icon].
  final Widget? leading;

  /// Pill text when it should be terser than the tooltip ("Stow").
  final String? shortLabel;

  static const double circleSize = 44;
  static const double squareSize = 50;
  static const _fill = Color(0x66141413);

  @override
  Widget build(BuildContext context) {
    final iconSized = iconOnly || square;
    final glyph =
        leading ?? Icon(icon, size: iconSized ? 20 : 18, color: iconColor);
    if (iconSized) {
      final size = square ? squareSize : circleSize;
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: SizedBox(
            width: size,
            height: size,
            child: IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                backgroundColor: _fill,
                foregroundColor: ArgosyColors.cream,
                shape: square
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: ArgosyColors.line3),
                      )
                    : const CircleBorder(
                        side: BorderSide(color: ArgosyColors.line2),
                      ),
                padding: EdgeInsets.zero,
              ),
              icon: glyph,
            ),
          ),
        ),
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: _fill,
        foregroundColor: ArgosyColors.cream,
        side: const BorderSide(color: ArgosyColors.line2),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      icon: glyph,
      label: Text(
        shortLabel ?? label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
