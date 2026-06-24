import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../util/format.dart';
import '../../widgets/arg_chip.dart';
import '../../widgets/async_view.dart';
import '../../widgets/hatch_pattern.dart';
import 'add_to_vault.dart';
import 'detail_providers.dart';
import 'detail_widgets.dart';
import 'label_editor.dart';

/// A series' detail screen: backdrop hero, your labels, Add-to-Vault, a season
/// selector, and the episode list with per-episode resume/play.
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({super.key, required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(seriesDetailProvider(seriesId));
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ArgosyColors.cream),
      ),
      body: AsyncView(
        value: detail,
        onRetry: () => ref.invalidate(seriesDetailProvider(seriesId)),
        builder: (series) => _Body(series: series),
      ),
    );
  }
}

/// A playable episode flattened with its season number, for resume targeting.
typedef _Playable = ({EpisodeSummary ep, int seasonNumber});

/// Folds consecutive episodes backed by the same file into one group. A combined
/// rip (e.g. The Good Place "E1" = EP1+EP2) yields several episode rows sharing a
/// mediaItemId; grouping them renders "E1–2" instead of a false missing-episode
/// gap. Episodes with no linked file each stand alone.
List<List<EpisodeSummary>> _groupEpisodes(List<EpisodeSummary> episodes) {
  final groups = <List<EpisodeSummary>>[];
  for (final e in episodes) {
    final prev = groups.isNotEmpty ? groups.last : null;
    if (e.mediaItemId != null && prev != null && prev.first.mediaItemId == e.mediaItemId) {
      prev.add(e);
    } else {
      groups.add([e]);
    }
  }
  return groups;
}

class _Body extends StatefulWidget {
  const _Body({required this.series});

  final SeriesDetail series;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int _activeSeason = 0;

  List<_Playable> get _playable => [
    for (final s in widget.series.seasons)
      for (final e in s.episodes)
        if (e.mediaItemId != null) (ep: e, seasonNumber: s.seasonNumber),
  ];

  static bool _touched(EpisodeSummary e) =>
      (e.watched ?? false) || (e.positionSeconds ?? 0) > 5;

  /// The episode to resume: the last in-progress one, else the one after the
  /// last episode you finished. Null when nothing's been started.
  _Playable? get _resumeTarget {
    final playable = _playable;
    var lastTouched = -1;
    for (var i = 0; i < playable.length; i++) {
      if (_touched(playable[i].ep)) lastTouched = i;
    }
    if (lastTouched == -1) return null;
    final last = playable[lastTouched];
    if (!(last.ep.watched ?? false) && (last.ep.positionSeconds ?? 0) > 5) {
      return last; // still mid-episode
    }
    return lastTouched + 1 < playable.length ? playable[lastTouched + 1] : null;
  }

  String? get _firstPlayable => _playable.firstOrNull?.ep.mediaItemId;

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final resume = _resumeTarget;
    final season = series.seasons.isEmpty
        ? null
        : series.seasons[_activeSeason];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailBackdrop(
          backdropUrl: series.backdropUrl,
          posterUrl: series.posterUrl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                series.title,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${series.seasons.length} season${series.seasons.length == 1 ? '' : 's'}'
                '${series.year != null ? '  •  ${series.year}' : ''}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: ArgosyColors.dim),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (series.overview != null && series.overview!.isNotEmpty) ...[
                Text(
                  series.overview!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              GenreTagChips(tags: series.tags),
              if (series.tags.isNotEmpty) const SizedBox(height: 16),
              _SeriesActions(
                seriesId: series.id,
                resume: resume,
                firstPlayable: _firstPlayable,
              ),
              const SizedBox(height: 20),
              LabelEditor(seriesId: series.id, initial: series.labels),
            ],
          ),
        ),
        if (series.seasons.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: series.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ArgChip(
                label:
                    series.seasons[i].title ??
                    'Season ${series.seasons[i].seasonNumber}',
                selected: i == _activeSeason,
                onTap: () => setState(() => _activeSeason = i),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (season != null)
          for (final group in _groupEpisodes(season.episodes))
            _EpisodeTile(episodes: group, seasonNumber: season.seasonNumber),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SeriesActions extends StatelessWidget {
  const _SeriesActions({
    required this.seriesId,
    required this.resume,
    required this.firstPlayable,
  });

  final String seriesId;
  final _Playable? resume;
  final String? firstPlayable;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (resume != null)
          FilledButton.icon(
            style: brassButtonStyle(context),
            onPressed: () =>
                openPlayer(context, resume!.ep.mediaItemId!, resume: true),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(
              'Resume S${resume!.seasonNumber} Ep ${resume!.ep.episodeNumber}',
            ),
          )
        else
          FilledButton.icon(
            style: brassButtonStyle(context),
            onPressed: firstPlayable == null
                ? null
                : () => openPlayer(context, firstPlayable!),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Play'),
          ),
        AddToVaultButton(seriesId: seriesId),
      ],
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({required this.episodes, required this.seasonNumber});

  /// One or more episode rows backed by a single file. Length > 1 is a combined
  /// rip; the first is the representative for runtime/progress/play.
  final List<EpisodeSummary> episodes;
  final int seasonNumber;

  EpisodeSummary get _rep => episodes.first;
  bool get _combined => episodes.length > 1;

  double get _percent {
    final dur = _rep.durationSeconds;
    final pos = _rep.positionSeconds;
    if (dur == null || dur == 0 || pos == null) return 0;
    return (pos / dur).clamp(0.0, 1.0).toDouble();
  }

  num get _remainingSeconds {
    final dur = _rep.durationSeconds ?? 0;
    final pos = _rep.positionSeconds ?? 0;
    return (dur - pos).clamp(0, dur);
  }

  // "E5" for a single episode, "E1–2" for a combined span.
  String get _episodeLabel => _combined
      ? 'E${episodes.first.episodeNumber}–${episodes.last.episodeNumber}'
      : 'E${_rep.episodeNumber}';

  // Real episode name(s) joined, or a plain "Episode N" / "Episodes N–M" fallback
  // until TMDB per-episode metadata lands.
  String get _displayTitle {
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

  String? get _stillPath => episodes
      .map((e) => e.stillUrl)
      .firstWhere((u) => u != null && u.isNotEmpty, orElse: () => null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final playable = _rep.mediaItemId != null;
    final watched = _rep.watched ?? false;
    final inProgress = _percent > 0 && !watched;
    final runtime = formatRuntime(_rep.durationSeconds);
    final overview = _overview;
    final still = ref.watch(artworkResolverProvider)(_stillPath);

    final status = !playable
        ? 'No file linked'
        : watched
        ? 'Watched'
        : inProgress
        ? '${(_percent * 100).round()}% · ${formatRuntime(_remainingSeconds)} left'
        : 'Not started';
    final statusLine = runtime.isNotEmpty && runtime != '—'
        ? '$status · $runtime'
        : status;

    return Opacity(
      opacity: playable ? 1 : 0.5,
      child: InkWell(
        onTap: playable ? () => openPlayer(context, _rep.mediaItemId!) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 16:9 episode thumbnail: the TMDB still when we have one, else a
              // branded hatch tile. The play/check glyph + resume bar sit on top.
              SizedBox(
                width: 124,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radius),
                      border: Border.all(color: tokens.line),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(tokens.radius),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (still != null)
                            Image.network(
                              still,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const HatchPlaceholder(),
                            )
                          else
                            const HatchPlaceholder(),
                          Center(
                            child: Icon(
                              watched ? Icons.check_circle : Icons.play_arrow,
                              size: watched ? 22 : 26,
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
                                minHeight: 3,
                                backgroundColor: tokens.line2,
                                valueColor: AlwaysStoppedAnimation(
                                  tokens.progress,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'S$seasonNumber · $_episodeLabel',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: ArgosyColors.accent,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                          ),
                          if (_combined) ...[
                            const SizedBox(width: 8),
                            _CombinedBadge(tokens: tokens),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (overview != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          overview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: ArgosyColors.dim),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        statusLine,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: inProgress
                                  ? ArgosyColors.soft2
                                  : ArgosyColors.faint,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small "Combined" pill marking an episode row backed by one shared file.
class _CombinedBadge extends StatelessWidget {
  const _CombinedBadge({required this.tokens});

  final ArgosyTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.line2),
      ),
      child: Text(
        'Combined',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: ArgosyColors.soft2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
