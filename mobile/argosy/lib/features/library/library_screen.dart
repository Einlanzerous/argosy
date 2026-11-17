import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/arg_chip.dart';
import '../../widgets/async_view.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import 'browse_filter.dart';
import 'library_controller.dart';
import 'library_filter_sheet.dart';

/// The Manifest — a poster grid across every library with the kind toggle,
/// sort cycle, and the faceted filter sheet.
///
/// The header is two rows on a phone (title / count / sort, then the kind chips
/// and a filter icon) and one row when expanded (ARGY-308). It used to carry an
/// eyebrow and a search bar as well; the bar duplicated the Search tab, which
/// is always one tap away in the nav.
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
            _Header(
              filter: filter,
              controller: controller,
              count: count,
              expanded: isExpandedWidth(context),
            ),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.filter,
    required this.controller,
    required this.count,
    required this.expanded,
  });

  final BrowseFilter filter;
  final LibraryFilterController controller;
  final int? count;
  final bool expanded;

  void _cycleSort() {
    const values = BrowseSort.values;
    controller.setSort(values[(filter.sort.index + 1) % values.length]);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final title = Text('Manifest', style: text.displaySmall);
    final countLabel = count == null
        ? null
        : Text(
            '$count ${count == 1 ? 'title' : 'titles'}',
            key: const ValueKey('manifest-count'),
            style: text.labelMedium,
          );
    final chips = _ScopeChips(filter: filter, controller: controller);
    final sort = _SortButton(sort: filter.sort, onCycle: _cycleSort);

    if (expanded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: Row(
          children: [
            // Capped (not Flexible: that would split the slack with the chip
            // row) so a narrow expanded window squeezes the title rather than
            // overflowing the single row.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                'Manifest',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.displaySmall,
              ),
            ),
            if (countLabel != null) ...[
              const SizedBox(width: 14),
              countLabel,
            ],
            const SizedBox(width: 24),
            Expanded(child: chips),
            const SizedBox(width: 12),
            _FilterButton(
              count: filter.activeCount,
              iconOnly: false,
              onTap: () => LibraryFilterSheet.show(context),
            ),
            const SizedBox(width: 10),
            sort,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: title),
              if (countLabel != null) ...[
                countLabel,
                const SizedBox(width: 12),
              ],
              sort,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: chips),
              const SizedBox(width: 8),
              _FilterButton(
                count: filter.activeCount,
                iconOnly: true,
                onTap: () => LibraryFilterSheet.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The All / Movies / Shows kind toggle.
class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.filter, required this.controller});

  final BrowseFilter filter;
  final LibraryFilterController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in LibraryScreen._scopeLabels.entries) ...[
            ArgChip(
              label: entry.value,
              selected: filter.scope == entry.key,
              onTap: () => controller.setScope(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
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

/// Opens the faceted filter sheet: a labelled button when expanded, a tune icon
/// (badged with the active-facet count) on a phone.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.count,
    required this.onTap,
    required this.iconOnly,
  });

  final int count;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final color = active ? ArgosyColors.accentHi : ArgosyColors.soft2;
    final side = BorderSide(
      color: active ? ArgosyColors.accentLine : ArgosyColors.line2,
    );
    if (iconOnly) {
      return Tooltip(
        message: active ? 'Filters ($count)' : 'Filters',
        child: IconButton(
          key: const ValueKey('manifest-filter-icon'),
          onPressed: onTap,
          style: IconButton.styleFrom(
            foregroundColor: color,
            side: side,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.argosy.radiusSm),
            ),
          ),
          icon: Badge(
            isLabelVisible: active,
            label: Text('$count'),
            backgroundColor: ArgosyColors.accent,
            textColor: ArgosyColors.ink,
            child: const Icon(Icons.tune, size: 20),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: side,
        // Shrink-wrap: the theme's default minimum width would fill the row.
        minimumSize: const Size(0, 40),
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

    final expanded = isExpandedWidth(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Expanded: up to six columns, fewer when the pane is narrower (a
        // 600dp window minus the rail is ~516dp), never smaller than ~140dp.
        final columns = (box.maxWidth / 140).floor().clamp(3, 6);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(expanded ? 24 : 18, 10, expanded ? 24 : 18, 28),
          gridDelegate: expanded
              ? SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                )
              : const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: 11,
                  mainAxisSpacing: 16,
                ),
          itemCount: cards.length,
          itemBuilder: (_, i) => MediaPosterCard(card: cards[i], width: 160),
        );
      },
    );
  }
}
