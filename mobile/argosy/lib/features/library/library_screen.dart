import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../widgets/arg_chip.dart';
import '../../widgets/async_view.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import 'browse_filter.dart';
import 'library_controller.dart';
import 'library_filter_sheet.dart';

/// The Manifest — a poster grid across every library with the kind toggle,
/// sort cycle, and the faceted filter sheet, under a framed header that doubles
/// as the entry point to Search.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  static const _scopeLabels = {
    BrowseScope.all: 'All',
    BrowseScope.movies: 'Movies',
    BrowseScope.series: 'Shows',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final controller = ref.read(libraryFilterProvider.notifier);
    final results = ref.watch(libraryResultsProvider);
    final count = results.value?.length;

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(count: count),
            _Controls(filter: filter, controller: controller, count: count),
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

/// Eyebrow + big title + titles count, then a tappable search bar that hands off
/// to the Search tab.
class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THE MANIFEST',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: ArgosyColors.accent,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manifest',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
              if (count != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$count\ntitles',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => openSearch(context),
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xB3141413),
                borderRadius: BorderRadius.circular(tokens.radiusLg),
                border: Border.all(color: tokens.line2),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: 19,
                    color: ArgosyColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Search the Manifest…',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: ArgosyColors.dim),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.filter,
    required this.controller,
    required this.count,
  });

  final BrowseFilter filter;
  final LibraryFilterController controller;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kind toggle as a chip row, with the faceted filter button trailing.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry
                          in LibraryScreen._scopeLabels.entries) ...[
                        ArgChip(
                          label: entry.value,
                          selected: filter.scope == entry.key,
                          onTap: () => controller.setScope(entry.key),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _FilterButton(
                count: filter.activeCount,
                onTap: () => LibraryFilterSheet.show(context),
              ),
            ],
          ),
        ),
        // "Showing N titles" + the sort cycle pill.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Row(
            children: [
              if (count != null)
                Text(
                  'Showing $count ${count == 1 ? 'title' : 'titles'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: ArgosyColors.mute),
                ),
              const Spacer(),
              _SortButton(
                sort: filter.sort,
                onCycle: () {
                  const values = BrowseSort.values;
                  final next = values[(filter.sort.index + 1) % values.length];
                  controller.setSort(next);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact pill that shows the active sort and cycles to the next on tap.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onCycle});

  final BrowseSort sort;
  final VoidCallback onCycle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    return Material(
      color: ArgosyColors.panel,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onCycle,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert, size: 16, color: ArgosyColors.accent),
              const SizedBox(width: 6),
              Text(
                sort.label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: ArgosyColors.soft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? ArgosyColors.accentHi : ArgosyColors.soft2,
        side: BorderSide(
          color: active ? ArgosyColors.accentLine : ArgosyColors.line2,
        ),
      ),
      icon: const Icon(Icons.tune, size: 18),
      label: Text(active ? 'Filters ($count)' : 'Filters'),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cards});

  final List<MediaCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                size: 56,
                color: ArgosyColors.faint,
              ),
              const SizedBox(height: 16),
              Text(
                'The hold is empty',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'No cargo matches this filter. Try clearing a facet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.52,
        crossAxisSpacing: 11,
        mainAxisSpacing: 16,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => MediaPosterCard(card: cards[i], width: 160),
    );
  }
}
