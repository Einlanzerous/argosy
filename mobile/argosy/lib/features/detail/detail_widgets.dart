import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../widgets/hatch_pattern.dart';

// The brass/ghost action-button styles now live in the shared theme module so
// every surface (detail row, Bridge hero, …) draws the same family. Re-exported
// here so existing callers keep importing them from `detail_widgets`.
export '../../theme/button_styles.dart' show brassButtonStyle, ghostButtonStyle;

/// The full-bleed backdrop at the top of a detail screen: landscape artwork
/// (falling back to the poster, then a hatch placeholder) under a charcoal
/// fade so the overlaid title stays legible.
class DetailBackdrop extends ConsumerWidget {
  const DetailBackdrop({
    super.key,
    required this.backdropUrl,
    required this.posterUrl,
    required this.child,
    this.height = 340,
  });

  final String? backdropUrl;
  final String? posterUrl;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final bg = art(backdropUrl ?? posterUrl);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bg != null)
            Image.network(bg, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const HatchPlaceholder())
          else
            const HatchPlaceholder(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66171717), Color(0xCC171717), ArgosyColors.bg],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(alignment: Alignment.bottomLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// A row of read-only metadata chips — genres (neutral) and path tags (brass).
class GenreTagChips extends StatelessWidget {
  const GenreTagChips({super.key, this.genres = const [], this.tags = const []});

  final List<String> genres;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    if (genres.isEmpty && tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          _Pill(label: g, color: ArgosyColors.soft2, border: tokens.line2),
        for (final t in tags)
          _Pill(
            label: t,
            color: ArgosyColors.accentHi,
            border: tokens.accentLine,
            fill: tokens.accentWash,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.border,
    this.fill,
  });

  final String label;
  final Color color;
  final Color border;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// The flag shown when Stevedore marked an item for metadata review.
class ReviewFlag extends StatelessWidget {
  const ReviewFlag({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.flag_outlined, size: 16, color: ArgosyColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Flagged for review — metadata may be incomplete.',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: ArgosyColors.danger),
          ),
        ),
      ],
    );
  }
}
