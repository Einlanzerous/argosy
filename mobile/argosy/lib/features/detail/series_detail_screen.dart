import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../util/format.dart';
import '../../widgets/arg_chip.dart';
import '../../widgets/async_view.dart';
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
    final season = series.seasons.isEmpty ? null : series.seasons[_activeSeason];

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
              Text(series.title,
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text(
                '${series.seasons.length} season${series.seasons.length == 1 ? '' : 's'}'
                '${series.year != null ? '  •  ${series.year}' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: ArgosyColors.dim),
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
                Text(series.overview!,
                    style: Theme.of(context).textTheme.bodyMedium),
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
                label: series.seasons[i].title ??
                    'Season ${series.seasons[i].seasonNumber}',
                selected: i == _activeSeason,
                onTap: () => setState(() => _activeSeason = i),
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (season != null)
          for (final ep in season.episodes)
            _EpisodeTile(episode: ep, seasonNumber: season.seasonNumber),
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
                'Resume S${resume!.seasonNumber} Ep ${resume!.ep.episodeNumber}'),
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

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.seasonNumber});

  final EpisodeSummary episode;
  final int seasonNumber;

  double get _percent {
    final dur = episode.durationSeconds;
    final pos = episode.positionSeconds;
    if (dur == null || dur == 0 || pos == null) return 0;
    return (pos / dur).clamp(0.0, 1.0).toDouble();
  }

  num get _remainingSeconds {
    final dur = episode.durationSeconds ?? 0;
    final pos = episode.positionSeconds ?? 0;
    return (dur - pos).clamp(0, dur);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
    final playable = episode.mediaItemId != null;
    final watched = episode.watched ?? false;
    final inProgress = _percent > 0 && !watched;
    final epTitle = formatTitle(episode.title);

    final lengthLabel =
        playable ? formatRuntime(episode.durationSeconds) : 'No file linked';

    // Fixed row height so a column of episodes stays uniform whether or not an
    // episode has an in-progress bar — the second line is laid out inside this
    // height, and single-line rows centre within it rather than growing.
    return Opacity(
      opacity: playable ? 1 : 0.5,
      child: InkWell(
        onTap: playable ? () => openPlayer(context, episode.mediaItemId!) : null,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // The play / watched icon takes the slot the number used to.
                SizedBox(
                  width: 36,
                  child: Icon(
                    watched ? Icons.check_circle : Icons.play_arrow,
                    size: watched ? 20 : 24,
                    color:
                        watched ? ArgosyColors.green : ArgosyColors.soft2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line 1: episode name with the runtime inline beside it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              epTitle.isEmpty
                                  ? 'Episode ${episode.episodeNumber}'
                                  : epTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lengthLabel.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Text(
                              '· $lengthLabel',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: ArgosyColors.dim),
                            ),
                          ],
                        ],
                      ),
                      // Line 2 (in progress only): a wide progress bar with
                      // "<pct>% · <remaining> left" beside it.
                      if (inProgress) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _percent,
                                  minHeight: 4,
                                  backgroundColor: tokens.line2,
                                  valueColor:
                                      AlwaysStoppedAnimation(tokens.progress),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              '${(_percent * 100).round()}% · ${formatRuntime(_remainingSeconds)} left',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: ArgosyColors.soft2),
                            ),
                          ],
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
