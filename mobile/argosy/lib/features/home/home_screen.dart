import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/button_styles.dart';
import '../../widgets/argosy_mark.dart';
import '../../widgets/async_view.dart';
import '../../widgets/hatch_pattern.dart';
import '../../widgets/media_rail.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import 'home_providers.dart';

/// The Bridge — Argosy's home. A hero spotlight over Continue Watching, On
/// Deck, and Newly Arrived rows, plus Vault and genre discovery rows when the
/// profile's home layout is `discovery`.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeDataProvider);
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
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(homeDataProvider),
        builder: (home) => RefreshIndicator(
          color: ArgosyColors.accent,
          backgroundColor: ArgosyColors.panel,
          onRefresh: () => ref.refresh(homeDataProvider.future),
          child: home.isEmpty
              ? const _HoldEmpty()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    if (home.hero != null) _Hero(hero: home.hero!),
                    const SizedBox(height: 20),
                    if (home.continueRow.isNotEmpty) ...[
                      // Continue Watching gets larger tiles — it's the primary
                      // "pick up where you left off" row and shouldn't feel
                      // squished against the rails below it. Tapping a tile
                      // resumes the item directly (its id is the playable
                      // episode/film), not a detour through detail.
                      _rail('Continue Watching', home.continueRow,
                          height: 296,
                          cardWidth: 158,
                          onCardTap: (c) =>
                              openPlayer(context, c.id, resume: true)),
                      const SizedBox(height: 24),
                    ],
                    if (home.onDeck.isNotEmpty) ...[
                      _rail('On Deck', home.onDeck),
                      const SizedBox(height: 24),
                    ],
                    if (home.recent.isNotEmpty) ...[
                      _rail('Newly Arrived', home.recent),
                      const SizedBox(height: 24),
                    ],
                    for (final row in home.vaultRows) ...[
                      _rail(row.title, row.cards),
                      const SizedBox(height: 24),
                    ],
                    for (final row in home.genreRows) ...[
                      _rail(row.title, row.cards),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _rail(
    String title,
    List<MediaCard> cards, {
    double height = 248,
    double cardWidth = 132,
    void Function(MediaCard card)? onCardTap,
  }) =>
      MediaRail(
        title: title,
        height: height,
        children: [
          for (final c in cards)
            MediaPosterCard(
              card: c,
              width: cardWidth,
              onTap: onCardTap == null ? null : () => onCardTap(c),
            ),
        ],
      );
}

/// The full-bleed spotlight. Tapping it opens the item's detail screen.
/// Slightly shorter than the detail-screen action row ([kActionButtonSize]),
/// so the hero's Resume/Details pair sits compactly over the artwork.
const _heroButtonSize = Size(0, 44);

class _Hero extends ConsumerWidget {
  const _Hero({required this.hero});

  final HomeHero hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final art = ref.watch(artworkResolverProvider);
    final bg = art(hero.backdropUrl ?? hero.posterUrl);

    return GestureDetector(
      onTap: () => openDetail(context, hero.kind, hero.detailId),
      child: SizedBox(
        height: 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bg != null)
              Image.network(bg, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const HatchPlaceholder())
            else
              const HatchPlaceholder(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33171717), Color(0xCC171717), ArgosyColors.bg],
                  stops: [0, 0.6, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hero.eyebrow.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ArgosyColors.accent,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hero.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  if (hero.subtitle != null && hero.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      hero.subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (hero.percent != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: hero.percent,
                        minHeight: 4,
                        backgroundColor: tokens.line2,
                        valueColor: AlwaysStoppedAnimation(tokens.progress),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (hero.playableId != null) ...[
                        FilledButton.icon(
                          style: brassButtonStyle(context,
                              minimumSize: _heroButtonSize),
                          onPressed: () => openPlayer(
                            context,
                            hero.playableId!,
                            resume: hero.percent != null,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: Text(hero.percent != null ? 'Resume' : 'Play'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      FilledButton.icon(
                        style: ghostButtonStyle(context,
                            minimumSize: _heroButtonSize),
                        onPressed: () =>
                            openDetail(context, hero.kind, hero.detailId),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldEmpty extends StatelessWidget {
  const _HoldEmpty();

  @override
  Widget build(BuildContext context) {
    // Stays scrollable so pull-to-refresh works on an empty hold.
    return ListView(
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.sailing_outlined, size: 64, color: ArgosyColors.faint),
        const SizedBox(height: 20),
        Center(
          child: Text('The hold is empty',
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            "Stevedore hasn't loaded any cargo yet. Point Argosy at your media "
            'folders and pull to refresh.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
