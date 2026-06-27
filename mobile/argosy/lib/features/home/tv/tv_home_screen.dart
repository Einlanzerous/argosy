import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../widgets/async_view.dart';
import '../../../widgets/hatch_pattern.dart';
import '../../browse/media_card.dart';
import '../home_providers.dart';

/// The Bridge on the 10-foot screen (ARGY-51 / `TVHome.dc.html`): a full-bleed
/// backdrop behind a hero spotlight (resume + cross-device progress) over the
/// Continue Watching rail and the rest of the home rows. Binds the same
/// [homeDataProvider] the phone home uses — only the layout + D-pad focus differ.
class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeDataProvider);
    // The nav rail lives *outside* the AsyncView so it exists from the first
    // frame and holds initial focus (autofocusActive) — content loads in behind
    // it. This avoids the route's modal scope self-focusing during the async gap
    // (which kills D-pad traversal); focus starts on the rail and Right enters
    // the content. The same pattern is used by the TV detail screens.
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            const TvNavRail(active: TvSection.home, autofocusActive: true),
            Expanded(
              child: AsyncView(
                value: data,
                onRetry: () => ref.invalidate(homeDataProvider),
                builder: (home) => _Home(home: home),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Home extends ConsumerWidget {
  const _Home({required this.home});

  final HomeData home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = home.hero;
    final art = ref.watch(artworkResolverProvider);
    final backdrop = art(hero?.backdropUrl ?? hero?.posterUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed backdrop behind everything (incl. the nav rail's edge).
        if (backdrop != null)
          Image.network(
            backdrop,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const HatchPlaceholder(),
          )
        else
          const HatchPlaceholder(),
        // Left-to-right + bottom-up scrims so the copy and rails read over art.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF7141413), Color(0xB3141413), Color(0x1A141413)],
              stops: [0, 0.4, 0.8],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [ArgosyColors.bg, Color(0x66171717), Color(0x00171717)],
              stops: [0.16, 0.52, 0.78],
            ),
          ),
        ),
        // The nav rail is rendered by the screen (outside the AsyncView); here we
        // only lay out the content that loads in behind it.
        home.isEmpty ? const _Empty() : _Page(home: home),
      ],
    );
  }
}

/// The vertical, D-pad-scrolling page: a tall hero that fills most of the
/// screen (so Continue Watching only peeks below), then every rail. A single
/// [ListView] inside the fixed [TvStage] canvas — focusing a rail tile scrolls
/// it into view (via [TvFocusable.ensureVisibleOnFocus]), leaving a sliver of
/// hero above to return to; focusing a hero action snaps back to the top so the
/// hero reads full-size instead of being pulled up tight against the rails.
class _Page extends StatefulWidget {
  const _Page({required this.home});

  final HomeData home;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.home;
    final rails = <Widget>[];

    void posterRail(String title, List<MediaCard> cards) {
      if (cards.isEmpty) return;
      rails.add(TvRail(
        title: title,
        // Fits the 2:3 poster (172×258) plus its title/subtitle without
        // overflowing the rail row.
        height: 340,
        gap: 24,
        children: [for (final c in cards) _PosterTile(card: c)],
      ));
    }

    if (home.continueRow.isNotEmpty) {
      rails.add(TvRail(
        title: 'Continue Watching',
        hint: 'pick up on any deck in your Fleet',
        accent: true,
        children: [for (final e in home.continueRow) _ContinueTile(entry: e)],
      ));
    }
    posterRail('On Deck', home.onDeck);
    posterRail('Newly Arrived', home.recent);
    for (final row in home.vaultRows) {
      posterRail(row.title, row.cards);
    }
    for (final row in home.genreRows) {
      posterRail(row.title, row.cards);
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(56, 96, 64, 56),
      children: [
        if (home.hero != null) _Hero(hero: home.hero!, onFocused: _toTop),
        for (final rail in rails) ...[
          const SizedBox(height: 40),
          rail,
        ],
      ],
    );
  }
}

/// The hero spotlight — eyebrow, big title, the resume progress, and the
/// Resume/Play + Details actions. The first action autofocuses so the remote
/// lands somewhere sensible on entry.
class _Hero extends StatelessWidget {
  const _Hero({required this.hero, required this.onFocused});

  final HomeHero hero;

  /// Called when a hero action is focused, to snap the page back to the top.
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    final isSeries = hero.kind == MediaKind.series;
    // A tall block so the hero fills most of the screen and the first rail only
    // peeks in below it. The eyebrow + title sit at the top; a Spacer pushes the
    // episode line, resume progress, and actions down to just above the Continue
    // Watching rail, with the backdrop showing through the gap between.
    return SizedBox(
      width: 780,
      height: 660,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync_alt, size: 18, color: ArgosyColors.accent),
              const SizedBox(width: 10),
              Text(
                hero.eyebrow.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: ArgosyColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatTitle(hero.title),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Archivo',
              fontSize: 68,
              height: 0.98,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
              color: ArgosyColors.cream,
            ),
          ),
          const Spacer(),
          if (hero.subtitle != null && hero.subtitle!.isNotEmpty) ...[
            Text(
              hero.subtitle!,
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: ArgosyColors.soft2,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (hero.percent != null) ...[
            SizedBox(
              width: 560,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: hero.percent,
                        minHeight: 7,
                        backgroundColor: ArgosyColors.line3,
                        valueColor:
                            const AlwaysStoppedAnimation(ArgosyColors.accent),
                      ),
                    ),
                  ),
                  if (hero.remainingLabel != null) ...[
                    const SizedBox(width: 18),
                    Text(
                      hero.remainingLabel!,
                      style: const TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ArgosyColors.soft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hero.playableId != null)
                _HeroButton(
                  label: hero.percent != null ? 'Resume' : 'Play',
                  icon: Icons.play_arrow,
                  primary: true,
                  onFocused: onFocused,
                  onSelect: () => openPlayer(
                    context,
                    hero.playableId!,
                    resume: hero.percent != null,
                  ),
                ),
              const SizedBox(width: 16),
              _HeroButton(
                label: isSeries ? 'Episodes' : 'Details',
                primary: false,
                onFocused: onFocused,
                onSelect: () => openDetail(context, hero.kind, hero.detailId),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.primary,
    required this.onSelect,
    required this.onFocused,
    this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback onSelect;

  /// Snap the page to the top when this action takes focus (instead of
  /// ensure-visible, which pulled the hero up tight against the rails).
  final VoidCallback onFocused;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 13,
      scale: 1.05,
      onFocusChange: (focused) {
        if (focused) onFocused();
      },
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 18),
        decoration: BoxDecoration(
          color: primary
              ? ArgosyColors.accent
              : const Color(0x66141413),
          borderRadius: BorderRadius.circular(13),
          border: primary ? null : Border.all(color: ArgosyColors.line3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 22,
                  color: primary ? ArgosyColors.ink : ArgosyColors.cream),
              const SizedBox(width: 11),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: primary ? 'Archivo' : 'HankenGrotesk',
                fontSize: 21,
                fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                color: primary ? ArgosyColors.ink : ArgosyColors.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 332×186 (16:9) Continue Watching tile: backdrop, title/sub, resume bar, and
/// a play glyph on focus. Selecting resumes the item directly (its id is the
/// playable episode/film), mirroring the phone's continue rail.
class _ContinueTile extends ConsumerWidget {
  const _ContinueTile({required this.entry});

  final ContinueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final img = art(entry.backdropUrl ?? entry.posterUrl);

    return TvFocusable(
      borderRadius: 16,
      ensureVisibleOnFocus: true,
      // Land lower in the viewport so a slice of the hero stays visible above
      // the Continue Watching rail when it takes focus from the hero.
      ensureVisibleAlignment: 0.32,
      onSelect: () => openPlayer(context, entry.id, resume: true),
      child: SizedBox(
        width: 332,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (img != null)
                      Image.network(
                        img,
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
                          colors: [Colors.transparent, Color(0xE00C0C0B)],
                          stops: [0.4, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatTitle(entry.title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: ArgosyColors.cream,
                            ),
                          ),
                          if (entry.subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              entry.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'HankenGrotesk',
                                fontSize: 14,
                                color: ArgosyColors.soft,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: entry.progress,
                        minHeight: 5,
                        backgroundColor: ArgosyColors.line3,
                        valueColor:
                            const AlwaysStoppedAnimation(ArgosyColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (entry.remainingLabel != null) ...[
              const SizedBox(height: 11),
              Text(
                entry.remainingLabel!,
                style: const TextStyle(
                  fontFamily: 'HankenGrotesk',
                  fontSize: 14,
                  color: ArgosyColors.mute,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 2:3 poster tile for the On Deck / Newly Arrived / Vault / genre rails.
/// Selecting opens the title's detail (series or film).
class _PosterTile extends ConsumerWidget {
  const _PosterTile({required this.card});

  final MediaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final img = art(card.posterUrl ?? card.backdropUrl);

    return TvFocusable(
      borderRadius: 13,
      ensureVisibleOnFocus: true,
      onSelect: () => openDetail(context, card.kind, card.id),
      child: SizedBox(
        width: 172,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: img != null
                    ? Image.network(
                        img,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const HatchPlaceholder(),
                      )
                    : const HatchPlaceholder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              formatTitle(card.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Archivo',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: ArgosyColors.cream,
              ),
            ),
            if (card.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                card.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'HankenGrotesk',
                  fontSize: 13,
                  color: ArgosyColors.mute,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sailing_outlined, size: 72, color: ArgosyColors.faint),
          SizedBox(height: 22),
          Text(
            'The hold is empty',
            style: TextStyle(
              fontFamily: 'Archivo',
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: ArgosyColors.cream,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Point Argosy at your media folders, then refresh from a phone or the web.',
            style: TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 18,
              color: ArgosyColors.dim,
            ),
          ),
        ],
      ),
    );
  }
}
