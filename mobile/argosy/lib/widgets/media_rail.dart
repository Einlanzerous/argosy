import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// A titled, horizontally-scrolling row of media tiles (posters) — the home
/// screen's "On Deck", genre rows, etc. Layout-only; callers supply the tiles.
class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.children,
    this.onSeeAll,
    this.height = 248,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSeeAll;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}

/// An empty-state rail body — a dashed-feeling hint shown when a row has no
/// content yet (used by the home placeholder until the API client lands).
class RailEmptyState extends StatelessWidget {
  const RailEmptyState({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: ArgosyColors.faint),
      ),
    );
  }
}
