import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../widgets/action_pill.dart';
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

/// The back affordance over the backdrop: a 40dp rounded square on a dark glass
/// fill, so it reads on bright key art where a bare arrow did not.
class DetailBackButton extends StatelessWidget {
  const DetailBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: MaterialLocalizations.of(context).backButtonTooltip,
        child: Material(
          color: const Color(0x8C141413),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
            side: const BorderSide(color: Color(0x29EAEAE5)),
          ),
          child: InkWell(
            key: const ValueKey('detail-back'),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.chevron_left,
                size: 26,
                color: ArgosyColors.cream,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanded (unfolded / tablet) detail layout (ARGY-311): the artwork
/// covers the whole screen, the title, actions and synopsis sit in a compact
/// translucent box anchored bottom-left, and an optional [side] pane (a series'
/// season panel) floats on the right. Replaces ARGY-308's two-pane split, which
/// squeezed the backdrop into the top of a 340dp column.
class FullBleedDetail extends ConsumerWidget {
  const FullBleedDetail({
    super.key,
    required this.backdropUrl,
    required this.posterUrl,
    required this.details,
    this.side,
  });

  final String? backdropUrl;
  final String? posterUrl;

  /// The show/film info box: title, meta, actions, synopsis, cast.
  final Widget details;

  /// Right-hand pane, scrolled independently (null for a film).
  final Widget? side;

  /// Width of the bottom-left info box.
  static const double detailsWidth = 380;

  static const _boxFill = Color(0xC7141413); // rgba(20,20,19,0.78)
  static const _sideFill = Color(0xF0171717); // rgba(23,23,23,0.94)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final bg = art(backdropUrl ?? posterUrl);
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final box = Container(
      key: const ValueKey('detail-info-box'),
      width: detailsWidth,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: _boxFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ArgosyColors.line),
      ),
      child: details,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bg != null)
          Image.network(
            bg,
            fit: BoxFit.cover,
            alignment: const Alignment(0.3, -0.4),
            errorBuilder: (_, _, _) => const HatchPlaceholder(),
          )
        else
          const HatchPlaceholder(),
        // Darken the left and bottom, where the box sits, and the very top so
        // the back button reads; the art stays bright on the right.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xB3171717), Color(0x40171717), Color(0x00171717)],
              stops: [0, 0.45, 0.8],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x80171717), Color(0x00171717), Color(0x00171717), Color(0xCC171717)],
              stops: [0, 0.18, 0.6, 1],
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The box hugs the bottom-left; on a short screen it scrolls rather
            // than overflowing under the app bar.
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                key: const ValueKey('detail-info-scroll'),
                padding: EdgeInsets.fromLTRB(24, top, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (c.maxHeight - top - 24).clamp(0, double.infinity),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [box],
                  ),
                ),
              ),
            ),
            if (side != null)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(0, top + 24, 24, 0),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _sideFill,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          border: Border.all(color: ArgosyColors.line),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(18),
                          ),
                          child: side,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A row of read-only genre chips.
class GenreTagChips extends StatelessWidget {
  const GenreTagChips({super.key, this.genres = const []});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    if (genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in genres)
          _Pill(label: g, color: ArgosyColors.soft2, border: tokens.line2),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.border,
  });

  final String label;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
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

/// A ghost-styled toggle that marks a title / season watched or unwatched
/// (ARGY-109), independent of playback progress. Owns its busy state and shows a
/// snackbar on failure; [onSet] performs the write (and typically refreshes the
/// surrounding screen) with the requested next state.
class WatchedButton extends ConsumerStatefulWidget {
  const WatchedButton({
    super.key,
    required this.watched,
    required this.onSet,
    this.watchedLabel = 'Watched',
    this.markLabel = 'Mark watched',
    this.iconOnly = false,
    this.square = false,
    this.scopeIcon,
  });

  /// A 50dp rounded-square icon button (the show-level action row).
  final bool square;

  /// A distinct glyph for a wider scope (the whole series), so two icon-only
  /// watched buttons side by side are not identical.
  final IconData? scopeIcon;

  final bool watched;
  final Future<void> Function(bool watched) onSet;
  final String watchedLabel;
  final String markLabel;

  /// Icon circle with the label as tooltip (compact season header).
  final bool iconOnly;

  @override
  ConsumerState<WatchedButton> createState() => _WatchedButtonState();
}

class _WatchedButtonState extends ConsumerState<WatchedButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSet(!widget.watched);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update watched state"),
            backgroundColor: ArgosyColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionPill(
      iconOnly: widget.iconOnly,
      square: widget.square,
      onPressed: _busy ? null : _toggle,
      icon:
          widget.scopeIcon ??
          (widget.watched ? Icons.check_circle : Icons.check_circle_outline),
      iconColor: widget.watched ? ArgosyColors.accent : null,
      label: widget.watched ? widget.watchedLabel : widget.markLabel,
    );
  }
}

/// The watched marker overlaid on episode/title artwork: a solid brass pill
/// with a dark check, mirroring the web's `.ep-watch.on` corner pill (ARGY-122).
/// Purely indicative — the toggle affordance is long-press on the row.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ArgosyColors.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(Icons.check, size: size, color: ArgosyColors.bg),
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
