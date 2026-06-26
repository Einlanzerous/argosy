import 'package:flutter/material.dart';

import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_scaffold.dart';

/// PR1 foundation placeholder for the TV home (`TVHome.dc.html`). It proves the
/// end-to-end D-pad loop — the nav rail, a focusable content row, and the focus
/// ring/scale — so the foundation can be verified on a real TV before the full
/// hero + Continue-Watching rails land in PR2.
class TvHomeScreen extends StatelessWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TvScaffold(
      section: TvSection.home,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 64, 64, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONTINUE WATCHING',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ArgosyColors.accent,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Argosy TV',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Foundation (PR1) — the full home lands in PR2.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ArgosyColors.soft,
                  ),
            ),
            const Spacer(),
            const _PlaceholderRail(),
          ],
        ),
      ),
    );
  }
}

/// A row of focusable 16:9 tiles, purely to exercise D-pad navigation + the
/// focus ring on-device until the real rails arrive.
class _PlaceholderRail extends StatelessWidget {
  const _PlaceholderRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(width: 28),
        itemBuilder: (context, i) => TvFocusable(
          borderRadius: 16,
          child: Container(
            width: 332,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2F3A), Color(0xFF12151B)],
              ),
              border: Border.all(color: ArgosyColors.line),
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(16),
            child: Text(
              'Title ${i + 1}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
    );
  }
}
