import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';
import '../theme/argosy_tokens.dart';

/// A pill chip in the Argosy style — brass-washed when selected, hairline
/// outline when not. Used for discovery/genre chips and filter toggles
/// (mirrors the web's discovery chips).
class ArgChip extends StatelessWidget {
  const ArgChip({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    final fg = selected ? ArgosyColors.accentHi : ArgosyColors.soft2;

    return Material(
      color: selected ? tokens.accentWash : ArgosyColors.panel,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? tokens.accentLine : tokens.line2),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
