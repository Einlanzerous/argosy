import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_backdrop_scaffold.dart';
import '../../../tv/tv_button.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../util/poster_gradient.dart';
import '../../../widgets/async_view.dart';
import '../../../widgets/hatch_pattern.dart';
import '../add_to_vault.dart';
import '../detail_providers.dart';

/// A series' detail on the 10-foot screen (ARGY-51 / `TVSeries.dc.html`): a left
/// column of show meta + Resume/Add over a right column of season tabs and a
/// D-pad episode list (16:9 stills, progress, status). Binds the same
/// [seriesDetailProvider] the phone detail uses.
class TvSeriesScreen extends ConsumerWidget {
  const TvSeriesScreen({super.key, required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(seriesDetailProvider(seriesId));
    // Nav rail outside the AsyncView so it holds focus from the first frame (see
    // TvHomeScreen). Right from the rail enters the meta column; Right again hops
    // into the episode list.
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            const TvNavRail(active: TvSection.library, autofocusActive: true),
            Expanded(
              child: AsyncView(
                value: detail,
                onRetry: () => ref.invalidate(seriesDetailProvider(seriesId)),
                builder: (series) => _Series(series: series),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A playable episode flattened with its season number, for resume targeting.
typedef _Playable = ({EpisodeSummary ep, int seasonNumber});

class _Series extends StatefulWidget {
  const _Series({required this.series});

  final SeriesDetail series;

  @override
  State<_Series> createState() => _SeriesState();
}

class _SeriesState extends State<_Series> {
  late int _activeSeason = _resumeSeasonIndex;

  /// The season tab to open on: the one holding the resume episode (mapping its
  /// 1-indexed seasonNumber → the matching season index), else 0 so a fresh,
  /// unwatched series still opens on Season 1.
  int get _resumeSeasonIndex {
    final target = _resumeTarget;
    if (target == null) return 0;
    final i = _series.seasons.indexWhere((s) => s.seasonNumber == target.seasonNumber);
    return i >= 0 ? i : 0;
  }

  // Cross-column D-pad hops (ARGY-51): the left actions and the right episode
  // list share no horizontal focus band when the list is short, so directional
  // traversal can't cross between them. We bridge it explicitly — RIGHT from the
  // meta column jumps to the first episode, LEFT from the episode list jumps back
  // to the primary action. Plain Focus interceptors (not FocusScope) so LEFT from
  // the actions still reaches the nav rail.
  final FocusNode _playFocus = FocusNode(debugLabel: 'series-play');
  final FocusNode _firstEpisodeFocus = FocusNode(debugLabel: 'series-ep0');

  SeriesDetail get _series => widget.series;

  @override
  void dispose() {
    _playFocus.dispose();
    _firstEpisodeFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onMetaKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.arrowRight &&
        _firstEpisodeFocus.context != null) {
      _firstEpisodeFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onEpisodesKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _playFocus.context != null) {
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<_Playable> get _playable => [
        for (final s in _series.seasons)
          for (final e in s.episodes)
            if (e.mediaItemId != null) (ep: e, seasonNumber: s.seasonNumber),
      ];

  static bool _touched(EpisodeSummary e) =>
      (e.watched ?? false) || (e.positionSeconds ?? 0) > 5;

  /// The episode to resume: the last in-progress one, else the one after the
  /// last finished episode. Null when nothing's been started.
  _Playable? get _resumeTarget {
    final playable = _playable;
    var lastTouched = -1;
    for (var i = 0; i < playable.length; i++) {
      if (_touched(playable[i].ep)) lastTouched = i;
    }
    if (lastTouched == -1) return null;
    final last = playable[lastTouched];
    if (!(last.ep.watched ?? false) && (last.ep.positionSeconds ?? 0) > 5) {
      return last;
    }
    return lastTouched + 1 < playable.length ? playable[lastTouched + 1] : null;
  }

  String? get _firstPlayable => _playable.isEmpty ? null : _playable.first.ep.mediaItemId;

  @override
  Widget build(BuildContext context) {
    final series = _series;
    final resume = _resumeTarget;
    final season =
        series.seasons.isEmpty ? null : series.seasons[_activeSeason];

    return TvBackdrop(
      backdropUrl: series.backdropUrl,
      posterUrl: series.posterUrl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 56, 64, 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 540,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onMetaKey,
                child: _Meta(
                  series: series,
                  resume: resume,
                  firstPlayable: _firstPlayable,
                  playFocus: _playFocus,
                ),
              ),
            ),
            const SizedBox(width: 64),
            Expanded(
              child: season == null
                  ? const SizedBox.shrink()
                  : _Episodes(
                      series: series,
                      season: season,
                      activeSeason: _activeSeason,
                      onSelectSeason: (i) => setState(() => _activeSeason = i),
                      firstEpisodeFocus: _firstEpisodeFocus,
                      onEpisodesKey: _onEpisodesKey,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.series,
    required this.resume,
    required this.firstPlayable,
    required this.playFocus,
  });

  final SeriesDetail series;
  final _Playable? resume;
  final String? firstPlayable;
  final FocusNode playFocus;

  @override
  Widget build(BuildContext context) {
    final count = series.seasons.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Series · $count season${count == 1 ? '' : 's'}',
          style: const TextStyle(
            fontFamily: 'Archivo',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.8,
            color: ArgosyColors.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          series.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Archivo',
            fontSize: 62,
            height: 0.96,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            color: ArgosyColors.cream,
          ),
        ),
        if (series.year != null) ...[
          const SizedBox(height: 16),
          Text('${series.year}', style: _dim),
        ],
        if (series.overview != null && series.overview!.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            series.overview!,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 19,
              height: 1.55,
              color: ArgosyColors.soft2,
            ),
          ),
        ],
        if (series.cast.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'CAST',
            style: TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: ArgosyColors.dim,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            series.cast.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 19,
              height: 1.5,
              color: ArgosyColors.soft2,
            ),
          ),
        ],
        const SizedBox(height: 30),
        if (resume != null)
          TvButton(
            label: 'Resume · S${resume!.seasonNumber} E${resume!.ep.episodeNumber}',
            icon: Icons.play_arrow,
            primary: true,
            focusNode: playFocus,
            onSelect: () =>
                openPlayer(context, resume!.ep.mediaItemId!, resume: true),
          )
        else if (firstPlayable != null)
          TvButton(
            label: 'Play',
            icon: Icons.play_arrow,
            primary: true,
            focusNode: playFocus,
            onSelect: () => openPlayer(context, firstPlayable!),
          ),
        const SizedBox(height: 18),
        TvButton.icon(
          icon: Icons.add,
          label: 'Add to Vault',
          onSelect: () => AddToVaultButton.showFor(context, seriesId: series.id),
        ),
      ],
    );
  }

  static const _dim = TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: ArgosyColors.soft,
  );
}

class _Episodes extends StatelessWidget {
  const _Episodes({
    required this.series,
    required this.season,
    required this.activeSeason,
    required this.onSelectSeason,
    required this.firstEpisodeFocus,
    required this.onEpisodesKey,
  });

  final SeriesDetail series;
  final SeasonSummary season;
  final int activeSeason;
  final ValueChanged<int> onSelectSeason;

  /// Focus target for the first episode tile — the destination of the meta
  /// column's RIGHT hop.
  final FocusNode firstEpisodeFocus;

  /// Intercepts LEFT on an episode tile to hop back to the primary action.
  final FocusOnKeyEventCallback onEpisodesKey;

  /// Folds consecutive episodes backed by the same file into one row (a combined
  /// rip), mirroring the phone detail so a shared file reads "E1–2" not a gap.
  static List<List<EpisodeSummary>> _group(List<EpisodeSummary> episodes) {
    final groups = <List<EpisodeSummary>>[];
    for (final e in episodes) {
      final prev = groups.isNotEmpty ? groups.last : null;
      if (e.mediaItemId != null &&
          prev != null &&
          prev.first.mediaItemId == e.mediaItemId) {
        prev.add(e);
      } else {
        groups.add([e]);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _group(season.episodes);
    final count = season.episodes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (series.seasons.length > 1)
              for (var i = 0; i < series.seasons.length; i++) ...[
                _SeasonTab(
                  label: series.seasons[i].title ??
                      'Season ${series.seasons[i].seasonNumber}',
                  active: i == activeSeason,
                  onSelect: () => onSelectSeason(i),
                ),
                const SizedBox(width: 12),
              ],
            const Spacer(),
            Text(
              '$count episode${count == 1 ? '' : 's'}',
              style: const TextStyle(
                fontFamily: 'HankenGrotesk',
                fontSize: 16,
                color: ArgosyColors.mute,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onEpisodesKey,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (_, i) => _EpisodeTile(
                episodes: groups[i],
                seasonNumber: season.seasonNumber,
                focusNode: i == 0 ? firstEpisodeFocus : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeasonTab extends StatelessWidget {
  const _SeasonTab({
    required this.label,
    required this.active,
    required this.onSelect,
  });

  final String label;
  final bool active;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 11,
      ensureVisibleOnFocus: true,
      onSelect: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
        decoration: BoxDecoration(
          color: active ? ArgosyColors.accentBg2 : ArgosyColors.panel,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: active ? ArgosyColors.accentLine : ArgosyColors.line2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Archivo',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: active ? ArgosyColors.accent : ArgosyColors.soft,
          ),
        ),
      ),
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.episodes,
    required this.seasonNumber,
    this.focusNode,
  });

  final List<EpisodeSummary> episodes;
  final int seasonNumber;
  final FocusNode? focusNode;

  EpisodeSummary get _rep => episodes.first;
  bool get _combined => episodes.length > 1;

  double get _percent {
    final dur = _rep.durationSeconds;
    final pos = _rep.positionSeconds;
    if (dur == null || dur == 0 || pos == null) return 0;
    return (pos / dur).clamp(0.0, 1.0).toDouble();
  }

  String get _tag => _combined
      ? 'S$seasonNumber · E${episodes.first.episodeNumber}–${episodes.last.episodeNumber}'
      : 'S$seasonNumber · E${_rep.episodeNumber}';

  String get _title {
    final names =
        episodes.map((e) => episodeName(e.title)).whereType<String>().toList();
    if (names.isNotEmpty) return names.join(' / ');
    return _combined
        ? 'Episodes ${episodes.first.episodeNumber}–${episodes.last.episodeNumber}'
        : 'Episode ${_rep.episodeNumber}';
  }

  String? get _overview => episodes
      .map((e) => e.overview)
      .firstWhere((o) => o != null && o.isNotEmpty, orElse: () => null);

  String? get _still => episodes
      .map((e) => e.stillUrl)
      .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playable = _rep.mediaItemId != null;
    final watched = _rep.watched ?? false;
    final inProgress = _percent > 0 && !watched;
    final still = ref.watch(artworkResolverProvider)(_still);
    final runtime = formatRuntime(_rep.durationSeconds);
    final overview = _overview;

    final status = !playable
        ? 'No file linked'
        : watched
            ? 'Watched'
            : inProgress
                ? '${formatRuntime((_rep.durationSeconds ?? 0) - (_rep.positionSeconds ?? 0))} left'
                : 'Not started';

    return Opacity(
      opacity: playable ? 1 : 0.55,
      child: TvFocusable(
        borderRadius: 16,
        scale: 1.02,
        focusOffset: 4,
        focusNode: focusNode,
        ensureVisibleOnFocus: true,
        onSelect: playable
            ? () => openPlayer(context, _rep.mediaItemId!, resume: inProgress)
            : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ArgosyColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ArgosyColors.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 236,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (still != null)
                          Image.network(
                            still,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _StillFallback(seed: _rep.id),
                          )
                        else
                          _StillFallback(seed: _rep.id),
                        Center(
                          child: Icon(
                            watched ? Icons.check_circle : Icons.play_arrow,
                            size: 30,
                            color: watched
                                ? ArgosyColors.green
                                : ArgosyColors.soft2,
                          ),
                        ),
                        if (inProgress)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: _percent,
                              minHeight: 5,
                              backgroundColor: ArgosyColors.line3,
                              valueColor: const AlwaysStoppedAnimation(
                                  ArgosyColors.accent),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _tag,
                          style: const TextStyle(
                            fontFamily: 'Archivo',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: ArgosyColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: ArgosyColors.cream,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (overview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'HankenGrotesk',
                          fontSize: 16,
                          height: 1.5,
                          color: ArgosyColors.dim,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      status,
                      style: TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: inProgress
                            ? ArgosyColors.accent
                            : ArgosyColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (runtime.isNotEmpty && runtime != '—')
                Text(
                  runtime,
                  style: const TextStyle(
                    fontFamily: 'HankenGrotesk',
                    fontSize: 16,
                    color: ArgosyColors.mute,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The episode-thumbnail fallback when there's no TMDB still: a seeded gradient
/// under the hatch texture, matching the phone detail.
class _StillFallback extends StatelessWidget {
  const _StillFallback({required this.seed});

  final String seed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: posterGradient(seed)),
      child: const HatchPattern(),
    );
  }
}
