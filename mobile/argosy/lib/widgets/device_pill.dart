import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// A small brass `⇄ <device>` chip showing the deck a playhead was last on, for
/// the cross-device resume affordance on the Bridge hero + Continue cards
/// (ARGY-98). Rendered only when the last-played device differs from this one.
class DevicePill extends StatelessWidget {
  const DevicePill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: ArgosyColors.accentBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ArgosyColors.accentLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '⇄ ',
            style: TextStyle(color: ArgosyColors.accentSoft, fontSize: 11),
          ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ArgosyColors.accentSoft,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
