import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/argosy_colors.dart';
import '../theme/breakpoints.dart';
import '../widgets/argosy_mark.dart';

/// The persistent bottom-nav shell wrapping the Bridge / Manifest / Search
/// branches. Each branch keeps its own navigation stack (an indexed stack), so
/// switching tabs preserves scroll position and any pushed detail screens.
class ScaffoldWithNav extends StatelessWidget {
  const ScaffoldWithNav({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) => navigationShell.goBranch(
    index,
    // Tapping the active tab again pops it to its initial route.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    // Wide windows (a foldable's inner screen, a phone held sideways) get a left
    // rail instead of the bottom bar (ARGY-308).
    if (isExpandedWidth(context)) {
      return Scaffold(
        backgroundColor: ArgosyColors.bg,
        body: Row(
          children: [
            _NavRail(
              selectedIndex: navigationShell.currentIndex,
              onSelected: _goBranch,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }
    // Landscape is screen-height constrained (notably the player and phones held
    // sideways), so drop the destination labels and tighten the bar to reclaim
    // vertical space; portrait keeps the labelled, full-height bar.
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        backgroundColor: ArgosyColors.bg2,
        indicatorColor: ArgosyColors.accentBg2,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        height: landscape ? 64 : null,
        labelBehavior: landscape
            ? NavigationDestinationLabelBehavior.alwaysHide
            : NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: ArgosyColors.accentHi),
            label: 'Bridge',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: ArgosyColors.accentHi),
            label: 'Manifest',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: ArgosyColors.accentHi),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}

/// The expanded-width navigation: an 84dp rail with the ship mark on top and the
/// three destinations labelled beneath it.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.selectedIndex, required this.onSelected});

  /// Rail width, per the fold design.
  static const double width = 84;

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    // The rail sizes itself to its widest label; pin it to the design's width.
    return SizedBox(
      width: width,
      child: NavigationRail(
        key: const ValueKey('nav-rail'),
        backgroundColor: ArgosyColors.bg2,
        indicatorColor: ArgosyColors.accentBg2,
        minWidth: width,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: label?.copyWith(color: ArgosyColors.accentHi),
        unselectedLabelTextStyle: label,
        leading: const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 12),
          child: ArgosyMark(size: 44),
        ),
        destinations: const [
          NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: ArgosyColors.accentHi),
            label: Text('Bridge'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view, color: ArgosyColors.accentHi),
            label: Text('Manifest'),
          ),
          NavigationRailDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: ArgosyColors.accentHi),
            label: Text('Search'),
          ),
        ],
      ),
    );
  }
}
