import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../widgets/async_view.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import 'browse_filter.dart';
import 'library_controller.dart';
import 'library_filter_sheet.dart';

/// The Manifest — a poster grid across every library with the kind toggle,
/// sort row, and the faceted filter sheet.
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

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'THE MANIFEST',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ArgosyColors.accent,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text('Library', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
      body: Column(
        children: [
          _Controls(filter: filter, controller: controller),
          const Divider(height: 1, color: ArgosyColors.line),
          Expanded(
            child: AsyncView(
              value: results,
              onRetry: () => ref.invalidate(libraryResultsProvider),
              builder: (cards) => _Grid(cards: cards),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.filter, required this.controller});

  final BrowseFilter filter;
  final LibraryFilterController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kind segmented toggle.
          SegmentedButton<BrowseScope>(
            segments: [
              for (final entry in LibraryScreen._scopeLabels.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {filter.scope},
            showSelectedIcon: false,
            onSelectionChanged: (s) => controller.setScope(s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final sort in BrowseSort.values) ...[
                        _SortChip(
                          sort: sort,
                          selected: filter.sort == sort,
                          onTap: () => controller.setSort(sort),
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
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.sort,
    required this.selected,
    required this.onTap,
  });

  final BrowseSort sort;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    return Material(
      color: selected ? tokens.accentWash : Colors.transparent,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
                color: selected ? tokens.accentLine : tokens.line2),
          ),
          child: Text(
            sort.label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? ArgosyColors.accentHi : ArgosyColors.soft2,
                ),
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
            color: active ? ArgosyColors.accentLine : ArgosyColors.line2),
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
              const Icon(Icons.inventory_2_outlined,
                  size: 56, color: ArgosyColors.faint),
              const SizedBox(height: 16),
              Text('The hold is empty',
                  style: Theme.of(context).textTheme.titleLarge),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.52,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => MediaPosterCard(card: cards[i], width: 160),
    );
  }
}
