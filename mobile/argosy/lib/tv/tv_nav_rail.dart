import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../theme/argosy_colors.dart';
import '../widgets/argosy_mark.dart';
import 'tv_focusable.dart';

/// The primary sections reachable from the TV nav rail.
enum TvSection { home, library, search, settings }

/// The 100px left navigation rail (ARGY-51 / `TVNav.dc.html`): logo at top,
/// Home / Library / Search icons, Settings pinned to the bottom. The active
/// section shows a brass left-bar + washed background; focus adds the ring+scale
/// from [TvFocusable].
class TvNavRail extends StatelessWidget {
  const TvNavRail({super.key, required this.active, this.autofocusActive = false});

  final TvSection active;

  /// When true, the active rail entry is the screen's autofocus target. Set by
  /// screens whose body has no focusable content of its own (the PR3 placeholder
  /// sections); content screens leave this false and autofocus their own primary
  /// action instead.
  final bool autofocusActive;

  static const _width = 100.0;

  void _go(BuildContext context, TvSection section) {
    switch (section) {
      case TvSection.home:
        context.go(Routes.home);
      case TvSection.library:
        context.go(Routes.library);
      case TvSection.search:
        context.go(Routes.search);
      case TvSection.settings:
        context.go(Routes.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      decoration: const BoxDecoration(
        color: ArgosyColors.bg2,
        border: Border(right: BorderSide(color: ArgosyColors.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 46),
          const ArgosyMark(size: 44),
          const SizedBox(height: 50),
          _NavItem(
            icon: Icons.home_outlined,
            section: TvSection.home,
            active: active == TvSection.home,
            autofocus: autofocusActive && active == TvSection.home,
            onSelect: () => _go(context, TvSection.home),
          ),
          const SizedBox(height: 18),
          _NavItem(
            icon: Icons.grid_view_outlined,
            section: TvSection.library,
            active: active == TvSection.library,
            autofocus: autofocusActive && active == TvSection.library,
            onSelect: () => _go(context, TvSection.library),
          ),
          const SizedBox(height: 18),
          _NavItem(
            icon: Icons.search,
            section: TvSection.search,
            active: active == TvSection.search,
            autofocus: autofocusActive && active == TvSection.search,
            onSelect: () => _go(context, TvSection.search),
          ),
          const Spacer(),
          _NavItem(
            icon: Icons.settings_outlined,
            section: TvSection.settings,
            active: active == TvSection.settings,
            autofocus: autofocusActive && active == TvSection.settings,
            onSelect: () => _go(context, TvSection.settings),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.section,
    required this.active,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final TvSection section;
  final bool active;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.centerLeft,
      clipBehavior: Clip.none,
      children: [
        // Active left-bar indicator.
        if (active)
          Positioned(
            left: -20,
            child: Container(
              width: 4,
              height: 34,
              decoration: const BoxDecoration(
                color: ArgosyColors.accent,
                borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
              ),
            ),
          ),
        TvFocusable(
          borderRadius: 16,
          scale: 1.08,
          autofocus: autofocus,
          onSelect: onSelect,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: active ? ArgosyColors.accentBg2 : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 28,
              color: active ? ArgosyColors.accent : ArgosyColors.dim,
            ),
          ),
        ),
      ],
    );
  }
}
