import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';
import 'tv_nav_rail.dart';
import 'tv_stage.dart';

/// Shared TV screen frame (ARGY-51): the persistent left [TvNavRail] plus the
/// screen's content. Top-level sections (Home/Library/Search/Settings) wrap
/// their body in this so the rail is always present and consistently focusable.
class TvScaffold extends StatelessWidget {
  const TvScaffold({super.key, required this.section, required this.child});

  /// Which rail entry is highlighted as active.
  final TvSection section;

  /// The screen body, laid out to the right of the rail.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            // The sections that use TvScaffold are the PR3 placeholders, whose
            // body has no focusable of its own — so the rail holds initial focus.
            TvNavRail(active: section, autofocusActive: true),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
