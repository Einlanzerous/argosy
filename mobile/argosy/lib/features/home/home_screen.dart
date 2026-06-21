import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../widgets/arg_chip.dart';
import '../../widgets/argosy_mark.dart';
import '../../widgets/media_rail.dart';
import '../../widgets/poster_card.dart';
import '../auth/auth_controller.dart';

/// Home placeholder. Real rows (On Deck / Continue / genre rails) are populated
/// once the Dart API client (ARGY-78) and browse screens (ARGY-47) land; for
/// now this exercises the shared widgets so the design language is visible end
/// to end.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _chip = 0;
  static const _chips = ['For you', 'Films', 'Series', 'Recently added'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const ArgosyMark(size: 26),
            const SizedBox(width: 10),
            Text('Argosy', style: Theme.of(context).appBarTheme.titleTextStyle),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
            tooltip: 'Search',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ArgChip(
                label: _chips[i],
                selected: i == _chip,
                onTap: () => setState(() => _chip = i),
              ),
            ),
          ),
          const SizedBox(height: 20),
          MediaRail(
            title: 'On Deck',
            onSeeAll: () {},
            children: [
              for (var i = 0; i < 6; i++)
                PosterCard(
                  title: 'Title ${i + 1}',
                  subtitle: i.isEven ? 'S1 · E${i + 1}' : '2024 · Film',
                  progress: i == 0 ? 0.42 : null,
                  onTap: () {},
                ),
            ],
          ),
          const SizedBox(height: 24),
          const MediaRail(
            title: 'Continue Watching',
            height: 60,
            children: [
              SizedBox(
                width: 320,
                child: RailEmptyState(label: 'Nothing in progress yet.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
