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
///
/// Height scales with the viewport so the artwork carries real weight on tall
/// screens (a 10" tablet in portrait) the way it already does in a phone's
/// short landscape — [heightFactor] is the fraction of screen height it claims,
/// floored at [minHeight] so a phone's landscape strip never shrinks below what
/// reads well. Films lean toward a full "hero" fill; series claim a little less
/// so the first episode rows peek below as a teaser.
class DetailBackdrop extends ConsumerWidget {
  const DetailBackdrop({
    super.key,
    required this.backdropUrl,
    required this.posterUrl,
    required this.child,
    this.heightFactor = 0.5,
    this.minHeight = 340,
  });

  final String? backdropUrl;
  final String? posterUrl;
  final Widget child;
  final double heightFactor;
  final double minHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final bg = art(backdropUrl ?? posterUrl);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final height = (screenHeight * heightFactor).clamp(minHeight, screenHeight);

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

/// A read-only "Cast" row — a "CAST" label above a comma-joined list of
/// top-billed names (plus the director, for films). Renders nothing when the
/// cast list is empty so items without credits degrade gracefully (ARGY-113).
class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.cast});

  final List<String> cast;

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CAST',
          style: text.labelSmall?.copyWith(
            color: ArgosyColors.dim,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          cast.join(', '),
          style: text.bodyMedium?.copyWith(color: ArgosyColors.soft2),
        ),
      ],
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
