import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// A titled horizontal rail for the TV home (ARGY-51 / `TVHome.dc.html`): a
/// brass tick + Archivo title (with an optional muted hint), over a horizontally
/// scrolling row of [children]. The tiles own their own focus + ensure-visible
/// (via [TvFocusable.ensureVisibleOnFocus]); this just lays out the header and
/// the scroller with the design's gaps and leading inset.
class TvRail extends StatelessWidget {
  const TvRail({
    super.key,
    required this.title,
    required this.children,
    this.hint,
    this.accent = false,
    this.height = 250,
    this.gap = 28,
  });

  final String title;
  final List<Widget> children;

  /// Muted helper text trailing the title (e.g. "pick up on any deck").
  final String? hint;

  /// The first/focused rail draws a brass tick + brighter title.
  final bool accent;

  /// Height of the tile row (varies: 16:9 continue tiles vs. 2:3 posters).
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 24,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: accent ? ArgosyColors.accent : ArgosyColors.line3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: ArgosyColors.cream,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 14),
                Text(
                  hint!,
                  style: const TextStyle(
                    fontFamily: 'HankenGrotesk',
                    fontSize: 16,
                    color: ArgosyColors.mute,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Leading inset so a focused first tile isn't flush to the edge, and
            // its brass ring/scale has room to breathe.
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            itemCount: children.length,
            separatorBuilder: (_, _) => SizedBox(width: gap),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}
