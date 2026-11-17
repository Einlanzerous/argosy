import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/breakpoints.dart';
import '../../theme/button_styles.dart';
import '../../widgets/argosy_mark.dart';
import '../../widgets/async_view.dart';
import '../../widgets/hatch_pattern.dart';
import '../../widgets/media_rail.dart';
import '../account/account_sheet.dart';
import '../browse/continue_card.dart';
import '../browse/media_card.dart';
import '../browse/media_poster_card.dart';
import '../stow/stow_controller.dart';
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
        // Expanded: the rail carries the brand, so only the avatar remains.
        title: isExpandedWidth(context)
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ArgosyMark(size: 44),
                  const SizedBox(width: 11),
                  Text(
                    'Argosy',
                    style: Theme.of(
                      context,
                    ).appBarTheme.titleTextStyle?.copyWith(fontSize: 23),
                  ),
                ],
              ),
        actions: [
          // The Hold lives in the app bar, not behind Settings: Settings can't
          // render without the server, and what's stowed has to be reachable
          // precisely when there is no server (ARGY-49).
          const _StowedButton(),
          _AccountButton(),
          const SizedBox(width: 14),
        ],
      ),
      body: AsyncView(
        value: data,
        keepStale: true,
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
                      if (isExpandedWidth(context))
                        _continueGrid(context, home.continueRow)
                      else
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

  /// Expanded: Continue Watching is a 4-up grid rather than a strip, so the
  /// whole row is visible at once on a wide screen (ARGY-308).
  Widget _continueGrid(BuildContext context, List<ContinueEntry> entries) {
    const gap = 14.0;
    const columns = 4;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Continue Watching',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final w = (box.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                key: const ValueKey('continue-grid'),
                spacing: gap,
                runSpacing: 18,
                children: [
                  for (final e in entries.take(8))
                    ContinueCard(
                      entry: e,
                      width: w,
                      onTap: () => openPlayer(context, e.id, resume: true),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

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

/// Opens The Hold, badged with a count when anything is stowed. Hidden when
/// nothing is — it earns its space in the bar only once it has something to
/// show.
class _StowedButton extends ConsumerWidget {
  const _StowedButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Playable items only: the badge answers "how much can I watch offline",
    // and an unfinished download is not an answer to that. It still shows up in
    // The Hold itself, where the question is about storage.
    final count =
        ref
            .watch(stowedItemsProvider)
            .value
            ?.where((e) => !e.incomplete)
            .length ??
        0;
    if (count == 0) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'The Hold — stowed for offline',
      onPressed: () => openStowed(context),
      icon: Badge.count(
        count: count,
        backgroundColor: ArgosyColors.accent,
        textColor: ArgosyColors.ink,
        child: const Icon(
          Icons.download_for_offline_outlined,
          color: ArgosyColors.cream,
        ),
      ),
    );
  }
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

  /// Resume plus the cross-device note. Compact: Resume fills the row and a
  /// two-line "from" over the device name sits right-aligned beside it.
  /// Expanded: a padded (not full-width) Resume with "from NAME" inline.
  Widget _heroResumeRow(BuildContext context, bool expanded) {
    final device = hero.deviceLabel;
    final brass = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: ArgosyColors.accentSoft,
      fontWeight: FontWeight.w600,
      fontSize: expanded ? 11.5 : 11,
      height: 1.3,
    );
    final button = FilledButton.icon(
      key: const ValueKey('hero-resume'),
      style: brassButtonStyle(context, minimumSize: const Size(0, 48)).copyWith(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: expanded ? 26 : 20),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      onPressed: () =>
          openPlayer(context, hero.playableId!, resume: hero.percent != null),
      icon: const Icon(Icons.play_arrow, size: 20),
      label: Text(hero.percent != null ? 'Resume' : 'Play'),
    );
    if (expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          if (device != null) ...[
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                'from $device',
                key: const ValueKey('hero-from'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: brass,
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: button),
        if (device != null) ...[
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Column(
              key: const ValueKey('hero-from'),
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('from', style: brass),
                Text(
                  device,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: brass,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final art = ref.watch(artworkResolverProvider);
    final bg = art(hero.backdropUrl ?? hero.posterUrl);
    final expanded = isExpandedWidth(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        expanded ? 24 : 14,
        4,
        expanded ? 24 : 14,
        0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radiusXl + 2),
        child: GestureDetector(
          onTap: () => openDetail(context, hero.kind, hero.detailId),
          child: SizedBox(
            // Expanded caps the hero so two rows of the Bridge stay visible
            // beneath it instead of one stretched poster.
            height: expanded ? 300 : 420,
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
                // A taller scrim: it starts higher and reaches full strength
                // sooner, so the text holds on a bright frame (ARGY-308).
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0xB3000000),
                        Color(0xF2000000),
                      ],
                      stops: [0.12, 0.55, 0.92],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    expanded ? 24 : 18,
                    0,
                    expanded ? 24 : 18,
                    expanded ? 22 : 18,
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(
                      // Expanded: the text is a left column, not a full-width
                      // line.
                      constraints: BoxConstraints(
                        maxWidth: expanded ? 520 : double.infinity,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            key: const ValueKey('hero-eyebrow'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xD10E0E0D),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: ArgosyColors.accentLine,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
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
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hero.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          // Compact: "S6 · E17 · title" left, "21m left" right,
                          // then the bar. Expanded: the line, then bar + label.
                          if (!expanded &&
                                  (hero.subtitle?.isNotEmpty ?? false) ||
                              !expanded && hero.remainingLabel != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hero.subtitle ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                                if (hero.remainingLabel != null)
                                  Text(
                                    hero.remainingLabel!,
                                    key: const ValueKey('hero-remaining'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: ArgosyColors.soft,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                              ],
                            ),
                          ] else if (expanded &&
                              (hero.subtitle?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 6),
                            Text(
                              hero.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (hero.percent != null) ...[
                            SizedBox(height: expanded ? 12 : 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
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
                                if (expanded &&
                                    hero.remainingLabel != null) ...[
                                  const SizedBox(width: 11),
                                  Text(
                                    hero.remainingLabel!,
                                    key: const ValueKey('hero-remaining'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: ArgosyColors.soft,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          if (hero.playableId != null) ...[
                            const SizedBox(height: 14),
                            _heroResumeRow(context, expanded),
                          ],
                        ],
                      ),
                    ),
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
            // Neutral for both audiences (ARGY-167): a member household can't
            // add media to someone else's server, and library roots aren't
            // manageable from mobile at all — so don't send anyone here.
            "Stevedore hasn't loaded any cargo yet. Once media is added to this "
            'server, pull to refresh.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
