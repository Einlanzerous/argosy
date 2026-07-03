import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../widgets/async_view.dart';
import '../../../widgets/hatch_pattern.dart';
import '../../browse/media_card.dart';
import '../browse_filter.dart';
import '../library_controller.dart';

/// The Manifest on the 10-foot screen (ARGY-51 / `TVLibrary.dc.html`): a 330px
/// facet side panel (Kind / Genre) over the brass-on-charcoal poster
/// grid. Binds the same [libraryFilterProvider] / [libraryResultsProvider] the
/// phone Manifest uses, plus [libraryFacetsProvider] for the genre counts — only
/// the layout + D-pad focus differ.
///
/// Focus flows left→right across three full-height columns: nav rail → facet
/// panel → grid. They're adjacent and span the full height, so Flutter's
/// directional traversal crosses them the same way it crosses the nav rail into
/// content elsewhere (no explicit hops needed — verified on the dongle).
class TvLibraryScreen extends ConsumerWidget {
  const TvLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(libraryResultsProvider);
    // Nav rail outside the AsyncView so it holds focus from the first frame
    // (see TvHomeScreen); the facet panel is static too, so only the grid waits.
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            const TvNavRail(active: TvSection.library, autofocusActive: true),
            const _FacetPanel(),
            Expanded(
              child: AsyncView(
                value: results,
                onRetry: () => ref.invalidate(libraryResultsProvider),
                builder: (cards) => _Grid(cards: cards),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The left facet rail: title block + Kind (scope) and Genre
/// (from [libraryFacetsProvider], with counts) groups.
class _FacetPanel extends ConsumerWidget {
  const _FacetPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final ctrl = ref.read(libraryFilterProvider.notifier);
    final facets = ref.watch(libraryFacetsProvider).value ?? const <Facet>[];
    final count = ref.watch(libraryResultsProvider).value?.length;

    final genres = facets.where((f) => f.type == FacetTypeEnum.genre).toList();

    return Container(
      width: 330,
      decoration: const BoxDecoration(
        color: ArgosyColors.bg2,
        border: Border(right: BorderSide(color: ArgosyColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(30, 56, 30, 40),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'THE MANIFEST',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.6,
                color: ArgosyColors.accent,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Library',
              style: TextStyle(
                fontFamily: 'Archivo',
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
                color: ArgosyColors.cream,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count == null
                  ? 'Reading the hold…'
                  : '$count ${count == 1 ? 'title' : 'titles'} in the hold',
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.mute,
              ),
            ),
            const SizedBox(height: 34),
            _FacetGroup(
              title: 'Kind',
              children: [
                _FacetRow(
                  label: 'All',
                  active: filter.scope == BrowseScope.all,
                  onSelect: () => ctrl.setScope(BrowseScope.all),
                ),
                _FacetRow(
                  label: 'Films',
                  active: filter.scope == BrowseScope.movies,
                  onSelect: () => ctrl.setScope(BrowseScope.movies),
                ),
                _FacetRow(
                  label: 'Series',
                  active: filter.scope == BrowseScope.series,
                  onSelect: () => ctrl.setScope(BrowseScope.series),
                ),
              ],
            ),
            if (genres.isNotEmpty) ...[
              const SizedBox(height: 28),
              _FacetGroup(
                title: 'Genre',
                children: [
                  for (final g in genres)
                    _FacetRow(
                      label: g.value,
                      count: g.count,
                      active: filter.genres.contains(g.value),
                      onSelect: () => ctrl.toggleGenre(g.value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FacetGroup extends StatelessWidget {
  const _FacetGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: ArgosyColors.faint,
            ),
          ),
        ),
        for (final child in children) ...[
          child,
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _FacetRow extends StatelessWidget {
  const _FacetRow({
    required this.label,
    required this.active,
    required this.onSelect,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onSelect;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 10,
      scale: 1.03,
      focusOffset: 3,
      ensureVisibleOnFocus: true,
      onSelect: onSelect,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          if (active)
            Positioned(
              left: 0,
              child: Container(
                width: 4,
                height: 20,
                decoration: const BoxDecoration(
                  color: ArgosyColors.accent,
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: active ? ArgosyColors.accentBg2 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: active ? ArgosyColors.accent : ArgosyColors.soft2,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: active ? ArgosyColors.accent : ArgosyColors.faint2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The poster grid + a header (scope title, count·sort line, sort cycle pill).
class _Grid extends ConsumerWidget {
  const _Grid({required this.cards});

  final List<MediaCard> cards;

  static const _scopeTitle = {
    BrowseScope.all: 'Everything',
    BrowseScope.movies: 'Films',
    BrowseScope.series: 'Series',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final ctrl = ref.read(libraryFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(46, 56, 64, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scopeTitle[filter.scope]!,
                      style: const TextStyle(
                        fontFamily: 'Archivo',
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: ArgosyColors.cream,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cards.length} ${cards.length == 1 ? 'title' : 'titles'} · sorted by ${filter.sort.label}',
                      style: const TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: ArgosyColors.mute,
                      ),
                    ),
                  ],
                ),
              ),
              _SortPill(
                sort: filter.sort,
                onCycle: () {
                  const values = BrowseSort.values;
                  ctrl.setSort(values[(filter.sort.index + 1) % values.length]);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: cards.isEmpty
                ? const _Empty()
                : GridView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 40, right: 8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 26,
                      crossAxisSpacing: 22,
                      childAspectRatio: 0.5,
                    ),
                    itemCount: cards.length,
                    itemBuilder: (_, i) => _PosterTile(card: cards[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  const _SortPill({required this.sort, required this.onCycle});

  final BrowseSort sort;
  final VoidCallback onCycle;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 11,
      scale: 1.05,
      onSelect: onCycle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: ArgosyColors.panel,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: ArgosyColors.line2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert, size: 18, color: ArgosyColors.accent),
            const SizedBox(width: 10),
            Text(
              sort.label,
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ArgosyColors.soft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 2:3 poster tile — backdrop, title, year·rating. Selecting opens the
/// title's detail (series or film). Mirrors the home rail's tile.
class _PosterTile extends ConsumerWidget {
  const _PosterTile({required this.card});

  final MediaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(artworkResolverProvider)(card.posterUrl ?? card.backdropUrl);

    return TvFocusable(
      borderRadius: 13,
      ensureVisibleOnFocus: true,
      onSelect: () => openDetail(context, card.kind, card.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: img != null
                  ? Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const HatchPlaceholder(),
                    )
                  : const HatchPlaceholder(),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatTitle(card.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ArgosyColors.cream,
            ),
          ),
          if (card.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              card.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: ArgosyColors.mute,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: ArgosyColors.faint),
          SizedBox(height: 18),
          Text(
            'The hold is empty',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: ArgosyColors.cream,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'No cargo matches this filter. Try clearing a facet.',
            style: TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 17,
              color: ArgosyColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}
