import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/api_providers.dart';
import '../../../api/artwork.dart';
import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_backdrop_scaffold.dart';
import '../../../tv/tv_button.dart';
import '../../../tv/tv_focusable.dart';
import '../../../tv/tv_landing_focus.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../util/poster_gradient.dart';
import '../../../widgets/async_view.dart';
import '../../../widgets/hatch_pattern.dart';
import '../add_to_vault.dart';
import '../detail_providers.dart';
import '../detail_widgets.dart';

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
        // Focus starts on the rail (it exists before the async detail does),
        // then the primary action claims it on mount unless the viewer already
        // moved — ARGY-173, the same arrangement as TV Home.
        child: TvLandingFocus(
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
      ),
    );
  }
}

/// A playable episode flattened with its season number, for resume targeting.
typedef _Playable = ({EpisodeSummary ep, int seasonNumber});

/// Room reserved inside the episode list for a focused row's brass ring
/// (ARGY-184). The list clips at its viewport and the rows run its full width,
/// so without this the ring is sliced on all four sides. Covers
/// [tvFocusClearance] for a row at this screen's width — 20.1px at the 1096px
/// the 1920×1080 [TvStage] gives the column.
const double _episodeFocusInset = 22;

class _Series extends ConsumerStatefulWidget {
  const _Series({required this.series});

  final SeriesDetail series;

  @override
  ConsumerState<_Series> createState() => _SeriesState();
}

class _SeriesState extends ConsumerState<_Series> {
  late int _activeSeason = _resumeSeasonIndex;

  /// Optimistic watched overrides keyed by backing-file id (ARGY-257), as on the
  /// phone detail. Not an invalidate-and-refetch: that swaps the screen for the
  /// loading spinner and drops focus off the toggle that was just pressed.
  final Map<String, bool> _watchedOverrides = {};

  bool _isWatched(EpisodeSummary e) {
    final id = e.mediaItemId;
    if (id != null && _watchedOverrides.containsKey(id)) {
      return _watchedOverrides[id]!;
    }
    return e.watched ?? false;
  }

  Future<void> _setWatched(String mediaItemId, bool next) async {
    await ref
        .read(libraryApiProvider)
        .setWatched(mediaItemId, WatchedUpdate(watched: next));
    if (mounted) setState(() => _watchedOverrides[mediaItemId] = next);
  }

  /// The season tab to open on: the one holding the resume episode (mapping its
  /// 1-indexed seasonNumber → the matching season index), else 0 so a fresh,
  /// unwatched series still opens on Season 1.
  int get _resumeSeasonIndex {
    final target = _resumeTarget;
    if (target == null) return 0;
    final i = _series.seasons.indexWhere(
      (s) => s.seasonNumber == target.seasonNumber,
    );
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
  void initState() {
    super.initState();
    // Land on Resume/Play rather than the nav rail (ARGY-173). No-ops if the
    // viewer moved focus while the detail loaded, or if there's nothing
    // playable to render the node.
    TvLandingFocus.claimOnMount(context, _playFocus);
  }

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

  String? get _firstPlayable =>
      _playable.isEmpty ? null : _playable.first.ep.mediaItemId;

  @override
  Widget build(BuildContext context) {
    final series = _series;
    final resume = _resumeTarget;
    final season = series.seasons.isEmpty
        ? null
        : series.seasons[_activeSeason];

    return TvBackdrop(
      backdropUrl: series.backdropUrl,
      posterUrl: series.posterUrl,
      child: Padding(
        // The episode list carries _episodeFocusInset inside itself, so the
        // margins around it give that much back and the rows stay where the
        // design puts them.
        padding: const EdgeInsets.fromLTRB(56, 56, 64 - _episodeFocusInset, 48),
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
            const SizedBox(width: 64 - _episodeFocusInset),
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
                      isWatched: _isWatched,
                      onSetWatched: _setWatched,
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
            label:
                'Resume · S${resume!.seasonNumber} E${resume!.ep.episodeNumber}',
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
          onSelect: () =>
              AddToVaultButton.showFor(context, seriesId: series.id),
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
    required this.isWatched,
    required this.onSetWatched,
  });

  final bool Function(EpisodeSummary) isWatched;
  final Future<void> Function(String mediaItemId, bool watched) onSetWatched;

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
        Padding(
          // Lines the season tabs up with the rows below, which start one
          // clearance in.
          padding: const EdgeInsets.symmetric(horizontal: _episodeFocusInset),
          child: Row(
            children: [
              if (series.seasons.length > 1)
                for (var i = 0; i < series.seasons.length; i++) ...[
                  _SeasonTab(
                    label:
                        series.seasons[i].title ??
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
        ),
        // The design's 24px under the tabs, less the clearance the list now
        // reserves above its first row.
        const SizedBox(height: 24 - _episodeFocusInset),
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onEpisodesKey,
            child: ListView.separated(
              // The list clips at its viewport and its rows run edge to edge, so
              // a focused row's ring only survives if the list carries the room
              // for it (ARGY-184).
              padding: const EdgeInsets.fromLTRB(
                _episodeFocusInset,
                _episodeFocusInset,
                _episodeFocusInset,
                _episodeFocusInset + 8,
              ),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (_, i) => _EpisodeRow(
                episodes: groups[i],
                seasonNumber: season.seasonNumber,
                focusNode: i == 0 ? firstEpisodeFocus : null,
                isWatched: isWatched,
                onSetWatched: onSetWatched,
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

/// An episode row plus its watched toggle (ARGY-257). Owns the two focus nodes
/// that let RIGHT / LEFT hop between them explicitly: the toggle floats over the
/// row's own rect, so directional traversal can't tell which is "to the right".
class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episodes,
    required this.seasonNumber,
    required this.isWatched,
    required this.onSetWatched,
    this.focusNode,
  });

  final List<EpisodeSummary> episodes;
  final int seasonNumber;
  final bool Function(EpisodeSummary) isWatched;
  final Future<void> Function(String mediaItemId, bool watched) onSetWatched;
  final FocusNode? focusNode;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  FocusNode? _ownRow;
  final FocusNode _toggle = FocusNode(debugLabel: 'episode-watched-toggle');

  FocusNode get _row =>
      widget.focusNode ?? (_ownRow ??= FocusNode(debugLabel: 'episode-row'));

  @override
  void dispose() {
    _ownRow?.dispose();
    _toggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EpisodeTile(
      episodes: widget.episodes,
      seasonNumber: widget.seasonNumber,
      isWatched: widget.isWatched,
      onSetWatched: widget.onSetWatched,
      focusNode: _row,
      toggleFocus: _toggle,
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.episodes,
    required this.seasonNumber,
    required this.isWatched,
    required this.onSetWatched,
    required this.focusNode,
    required this.toggleFocus,
  });

  final bool Function(EpisodeSummary) isWatched;
  final Future<void> Function(String mediaItemId, bool watched) onSetWatched;
  final List<EpisodeSummary> episodes;
  final int seasonNumber;
  final FocusNode focusNode;
  final FocusNode toggleFocus;

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
    final names = episodes
        .map((e) => episodeName(e.title))
        .whereType<String>()
        .toList();
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
    final watched = episodes.every(isWatched);
    final inProgress = _percent > 0 && !watched;
    final still = ref.watch(artworkResolverProvider)(_still);
    final runtime = formatRuntime(_rep.durationSeconds);
    final rating = episodeRatingLabel(episodes.map((e) => e.rating));
    final overview = _overview;

    final status = !playable
        ? 'No file linked'
        : watched
        ? 'Watched'
        : inProgress
        ? '${formatRuntime((_rep.durationSeconds ?? 0) - (_rep.positionSeconds ?? 0))} left'
        : 'Not started';

    final tile = Opacity(
      opacity: playable ? 1 : 0.55,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, e) {
          if (playable &&
              e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.arrowRight &&
              toggleFocus.context != null) {
            toggleFocus.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
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
                        const Center(
                          child: Icon(
                            Icons.play_arrow,
                            size: 30,
                            color: ArgosyColors.soft2,
                          ),
                        ),
                        if (watched)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: WatchedBadge(size: 18),
                          ),
                        if (inProgress)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: _percent,
                              minHeight: 5,
                              backgroundColor: ArgosyColors.line3,
                              valueColor: const AlwaysStoppedAnimation(
                                ArgosyColors.accent,
                              ),
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
                        if (rating != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            rating,
                            key: const ValueKey('episode-rating'),
                            style: const TextStyle(
                              fontFamily: 'Archivo',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ArgosyColors.accent,
                            ),
                          ),
                        ],
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
              // Room for the watched toggle floated over this edge.
              if (playable) const SizedBox(width: 72),
            ],
          ),
        ),
        ),
      ),
    );

    if (!playable) return tile;
    // The toggle floats over the row's right edge (the row reserves the room
    // beside its runtime) rather than sitting next to it, so the row keeps the
    // design's full width. RIGHT from the row reaches it; the row stays the
    // Select-to-play target, so a stray OK press never flips watched state
    // (ARGY-257).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          right: 16,
          top: 0,
          bottom: 0,
          child: Center(
            child: _EpisodeWatchedToggle(
              watched: watched,
              focusNode: toggleFocus,
              rowFocus: focusNode,
              onSet: (next) async {
                for (final e in episodes) {
                  await onSetWatched(e.mediaItemId!, next);
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A square D-pad toggle over an episode row's right edge: SELECT marks the episode
/// watched or unwatched. LEFT returns to the row it belongs to — the list's own
/// LEFT interceptor would otherwise jump past it to the primary action.
class _EpisodeWatchedToggle extends StatefulWidget {
  const _EpisodeWatchedToggle({
    required this.watched,
    required this.onSet,
    required this.focusNode,
    required this.rowFocus,
  });

  final FocusNode focusNode;
  final FocusNode rowFocus;
  final bool watched;
  final Future<void> Function(bool watched) onSet;

  @override
  State<_EpisodeWatchedToggle> createState() => _EpisodeWatchedToggleState();
}

class _EpisodeWatchedToggleState extends State<_EpisodeWatchedToggle> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onSet(!widget.watched);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't update watched state"),
            backgroundColor: ArgosyColors.danger,
          ),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final watched = widget.watched;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.rowFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        label: watched ? 'Mark unwatched' : 'Mark watched',
        child: TvFocusable(
          borderRadius: 13,
          scale: 1.05,
          focusNode: widget.focusNode,
          ensureVisibleOnFocus: true,
          onSelect: _toggle,
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x66141413),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: ArgosyColors.line3),
            ),
            child: Icon(
              watched ? Icons.check_circle : Icons.check_circle_outline,
              size: 28,
              color: watched ? ArgosyColors.accent : ArgosyColors.cream,
            ),
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
