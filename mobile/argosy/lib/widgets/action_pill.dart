import 'package:flutter/material.dart';

import '../theme/argosy_tokens.dart';
import '../theme/button_styles.dart';

/// A secondary action drawn two ways: a labelled ghost pill (expanded layouts)
/// or a 44dp icon circle with the label as its tooltip and semantics (compact
/// layouts, where several actions share the season header). Same action either
/// way; only the presentation changes.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconOnly = false,
    this.iconColor,
    this.leading,
  });

  /// Glyph, ignored when [leading] is given (e.g. a progress ring).
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool iconOnly;
  final Color? iconColor;

  /// A custom leading widget in place of [icon].
  final Widget? leading;

  static const double circleSize = 44;

  @override
  Widget build(BuildContext context) {
    final glyph =
        leading ?? Icon(icon, size: iconOnly ? 20 : 18, color: iconColor);
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: SizedBox(
            width: circleSize,
            height: circleSize,
            child: IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x66141413),
                shape: CircleBorder(
                  side: BorderSide(color: context.argosy.line2),
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
      style: ghostButtonStyle(context, minimumSize: const Size(0, 40)),
      onPressed: onPressed,
      icon: glyph,
      label: Text(label),
    );
  }
}
