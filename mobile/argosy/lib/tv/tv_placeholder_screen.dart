import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';
import 'tv_nav_rail.dart';
import 'tv_scaffold.dart';

/// A stand-in section body used by PR1 for the TV sections not yet built
/// (Library / Search / Settings). It keeps the nav rail navigable end-to-end so
/// the foundation is verifiable; each section's real screen replaces it in a
/// later PR.
class TvPlaceholderScreen extends StatelessWidget {
  const TvPlaceholderScreen({
    super.key,
    required this.section,
    required this.title,
    required this.note,
  });

  final TvSection section;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return TvScaffold(
      section: section,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 64, 64, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              note,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: ArgosyColors.soft),
            ),
          ],
        ),
      ),
    );
  }
}
