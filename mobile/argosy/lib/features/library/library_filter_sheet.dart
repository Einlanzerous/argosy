import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../widgets/arg_chip.dart';
import 'browse_filter.dart';
import 'library_controller.dart';

/// The faceted filter panel, shown as a draggable bottom sheet: genre chips,
/// watched state, a rating-floor slider, and a year range.
class LibraryFilterSheet extends ConsumerWidget {
  const LibraryFilterSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: ArgosyColors.panel,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => const LibraryFilterSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(libraryFilterProvider);
    final controller = ref.read(libraryFilterProvider.notifier);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Filters',
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              if (filter.hasFacets)
                TextButton(
                  onPressed: controller.clearFacets,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _Facet(
            label: 'Genre',
            child: _ChipWrap(
              items: kGenres,
              isOn: filter.genres.contains,
              onTap: controller.toggleGenre,
            ),
          ),
          _Facet(
            label: 'Watched',
            child: _ChipWrap(
              items: WatchedState.values.map((w) => w.label).toList(),
              isOn: (l) => filter.watched?.label == l,
              onTap: (l) => controller.setWatched(
                  WatchedState.values.firstWhere((w) => w.label == l)),
            ),
          ),
          _Facet(
            label: 'Rating',
            child: _RatingSlider(
              value: (filter.ratingMin ?? 0).toDouble(),
              onChanged: controller.setRatingMin,
            ),
          ),
          _Facet(
            label: 'Year',
            child: _YearRange(
              from: filter.yearFrom,
              to: filter.yearTo,
              onFrom: controller.setYearFrom,
              onTo: controller.setYearTo,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Show results'),
          ),
        ],
      ),
    );
  }
}

class _Facet extends StatelessWidget {
  const _Facet({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ArgosyColors.faint,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.items,
    required this.isOn,
    required this.onTap,
  });

  final List<String> items;
  final bool Function(String) isOn;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ArgChip(
            label: item,
            selected: isOn(item),
            onTap: () => onTap(item),
          ),
      ],
    );
  }
}

class _RatingSlider extends StatelessWidget {
  const _RatingSlider({required this.value, required this.onChanged});

  final double value;
  final void Function(num?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value,
            max: 10,
            divisions: 20,
            activeColor: ArgosyColors.accent,
            label: value > 0 ? '★ ${value.toStringAsFixed(1)}+' : 'Any',
            onChanged: (v) => onChanged(v),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            value > 0 ? '★ ${value.toStringAsFixed(1)}+' : 'Any',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

class _YearRange extends StatelessWidget {
  const _YearRange({
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
  });

  final int? from;
  final int? to;
  final void Function(int?) onFrom;
  final void Function(int?) onTo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _YearField(hint: 'From', value: from, onChanged: onFrom)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('–', style: TextStyle(color: ArgosyColors.faint)),
        ),
        Expanded(child: _YearField(hint: 'To', value: to, onChanged: onTo)),
      ],
    );
  }
}

class _YearField extends StatefulWidget {
  const _YearField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;
  final int? value;
  final void Function(int?) onChanged;

  @override
  State<_YearField> createState() => _YearFieldState();
}

class _YearFieldState extends State<_YearField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(hintText: widget.hint, isDense: true),
      onChanged: (raw) {
        final trimmed = raw.trim();
        widget.onChanged(trimmed.isEmpty ? null : int.tryParse(trimmed));
      },
    );
  }
}
