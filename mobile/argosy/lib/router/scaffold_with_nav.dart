import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/argosy_colors.dart';

/// The persistent bottom-nav shell wrapping the Bridge / Library / Search
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
        height: landscape ? 52 : null,
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
            label: 'Library',
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
