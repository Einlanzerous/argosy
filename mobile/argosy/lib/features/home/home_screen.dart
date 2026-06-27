import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/button_styles.dart';
import '../../widgets/argosy_mark.dart';
import '../../widgets/async_view.dart';
import '../../widgets/device_pill.dart';
import '../../widgets/hatch_pattern.dart';
import '../../widgets/media_rail.dart';
import '../account/account_sheet.dart';
import '../browse/continue_card.dart';
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
        // The logo-only ship mark + a separate "Argosy" wordmark (not the
        // combined logo-with-text image), so the two can be sized independently.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArgosyMark(size: 44),
            const SizedBox(width: 11),
            Text(
              'Argosy',
              style: Theme.of(context)
                  .appBarTheme
                  .titleTextStyle
                  ?.copyWith(fontSize: 23),
            ),
          ],
        ),
        actions: [_AccountButton(), const SizedBox(width: 14)],
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
                      // Continue Watching uses wide 16:9 tiles — it's the primary
                      // "pick up where you left off" row and reads like a strip of
                      // live screens. Tapping a tile resumes the item directly (its
                      // id is the playable episode/film), not a detour through
                      // detail.
                      _continueRail(context, home.continueRow),
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
  }) => MediaRail(
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

  Widget _continueRail(BuildContext context, List<ContinueEntry> entries) =>
      MediaRail(
        title: 'Continue Watching',
        height: 172,
        children: [
          for (final e in entries)
            ContinueCard(
              entry: e,
              onTap: () => openPlayer(context, e.id, resume: true),
            ),
        ],
      );
}

/// The Bridge's brass identity avatar — opens the account / Fleet sheet. Neutral
/// person glyph (we don't fabricate an initial without a known profile name).
class _AccountButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => AccountSheet.show(context),
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ArgosyColors.accent, Color(0xFF7A5D2C)],
          ),
          border: Border.all(color: ArgosyColors.line3),
        ),
        child: const Icon(Icons.person, size: 19, color: ArgosyColors.ink),
      ),
    );
  }
}

/// The Bridge spotlight — a framed, rounded hero card. Tapping the artwork opens
/// the item's detail screen; the full-width brass button resumes (or plays). The
/// remaining-time label sits beside the resume progress bar.
class _Hero extends ConsumerWidget {
  const _Hero({required this.hero});

  final HomeHero hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final art = ref.watch(artworkResolverProvider);
    final bg = art(hero.backdropUrl ?? hero.posterUrl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusXl + 2),
        child: GestureDetector(
          onTap: () => openDetail(context, hero.kind, hero.detailId),
          child: SizedBox(
            height: 420,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bg != null)
                  Image.network(
                    bg,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const HatchPlaceholder(),
                  )
                else
                  const HatchPlaceholder(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x99000000),
                        Color(0xF2000000),
                      ],
                      stops: [0.3, 0.7, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.sync_alt,
                            size: 13,
                            color: ArgosyColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hero.eyebrow.toUpperCase(),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: ArgosyColors.accent,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hero.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                      if (hero.subtitle != null &&
                          hero.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          hero.subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (hero.deviceLabel != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DevicePill(label: 'Left off on ${hero.deviceLabel!}'),
                        ),
                      ],
                      if (hero.percent != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: hero.percent,
                                  minHeight: 4,
                                  backgroundColor: tokens.line2,
                                  valueColor: AlwaysStoppedAnimation(
                                    tokens.progress,
                                  ),
                                ),
                              ),
                            ),
                            if (hero.remainingLabel != null) ...[
                              const SizedBox(width: 11),
                              Text(
                                hero.remainingLabel!,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: ArgosyColors.soft),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (hero.playableId != null) ...[
                        const SizedBox(height: 15),
                        FilledButton.icon(
                          style: brassButtonStyle(
                            context,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: () => openPlayer(
                            context,
                            hero.playableId!,
                            resume: hero.percent != null,
                          ),
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: Text(hero.percent != null ? 'Resume' : 'Play'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
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
          child: Text(
            'The hold is empty',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
