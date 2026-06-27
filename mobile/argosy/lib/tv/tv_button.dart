import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';
import 'tv_focusable.dart';

/// The 10-foot action button used across the TV detail + player chrome
/// (ARGY-51): brass primary, dark "ghost" secondary, or a square icon-only
/// variant (the `+` / search affordances). Wraps [TvFocusable] so it grows + rings
/// on focus like everything else; pass [autofocus] to make it the entry target.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onSelect,
    this.icon,
    this.primary = false,
    this.autofocus = false,
    this.iconOnly = false,
    this.focusNode,
  });

  /// Icon-only square button — [label] is still required for semantics but not
  /// drawn (e.g. the `+` add-to-vault affordance).
  factory TvButton.icon({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onSelect,
    bool autofocus = false,
  }) =>
      TvButton(
        key: key,
        label: label,
        icon: icon,
        onSelect: onSelect,
        autofocus: autofocus,
        iconOnly: true,
      );

  final String label;
  final VoidCallback onSelect;
  final IconData? icon;
  final bool primary;
  final bool autofocus;
  final bool iconOnly;

  /// Supplied when a caller needs to drive focus to this button explicitly —
  /// e.g. the series detail's cross-column D-pad hops (ARGY-51).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? ArgosyColors.ink : ArgosyColors.cream;
    return TvFocusable(
      borderRadius: 13,
      scale: 1.05,
      autofocus: autofocus,
      focusNode: focusNode,
      ensureVisibleOnFocus: true,
      onSelect: onSelect,
      child: Container(
        width: iconOnly ? 64 : null,
        height: iconOnly ? 64 : null,
        alignment: iconOnly ? Alignment.center : null,
        padding: iconOnly
            ? null
            : const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
        decoration: BoxDecoration(
          color: primary ? ArgosyColors.accent : const Color(0x66141413),
          borderRadius: BorderRadius.circular(13),
          border: primary ? null : Border.all(color: ArgosyColors.line3),
        ),
        child: iconOnly
            ? Icon(icon, size: 26, color: fg)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: fg),
                    const SizedBox(width: 11),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: primary ? 'Archivo' : 'HankenGrotesk',
                      fontSize: 21,
                      fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
