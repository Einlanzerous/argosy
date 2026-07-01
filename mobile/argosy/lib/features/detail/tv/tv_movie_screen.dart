import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../router/app_router.dart';
import '../../../theme/argosy_colors.dart';
import '../../../tv/tv_backdrop_scaffold.dart';
import '../../../tv/tv_button.dart';
import '../../../tv/tv_nav_rail.dart';
import '../../../tv/tv_stage.dart';
import '../../../util/format.dart';
import '../../../widgets/async_view.dart';
import '../add_to_vault.dart';
import '../detail_providers.dart';

/// A film's detail on the 10-foot screen (ARGY-51 / `TVMovie.dc.html`): backdrop
/// + metadata over Resume / Play-from-start / Add actions, with the resume bar
/// when there's saved progress. Binds the same [movieDetailProvider] the phone
/// detail uses. The system BACK key pops to wherever you came from.
class TvMovieScreen extends ConsumerWidget {
  const TvMovieScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(movieDetailProvider(itemId));
    // Nav rail outside the AsyncView so it holds focus from the first frame (see
    // TvHomeScreen). The system BACK key pops to wherever you came from.
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: TvStage(
        child: Row(
          children: [
            const TvNavRail(active: TvSection.library, autofocusActive: true),
            Expanded(
              child: AsyncView(
                value: detail,
                onRetry: () => ref.invalidate(movieDetailProvider(itemId)),
                builder: (data) => _Movie(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Movie extends StatelessWidget {
  const _Movie({required this.data});

  final MovieDetailData data;

  bool get _resumable {
    final p = data.progress;
    return p != null && !p.watched && p.positionSeconds > 5;
  }

  double get _percent {
    final p = data.progress;
    if (p == null || p.durationSeconds == null || p.durationSeconds == 0) {
      return 0;
    }
    return (p.positionSeconds / p.durationSeconds!).clamp(0.0, 1.0).toDouble();
  }

  /// A friendly container label for the eyebrow (the raw ffprobe value can be an
  /// ugly comma list like `matroska,webm`). Null when there's nothing useful.
  static String? _container(String? c) {
    if (c == null || c.isEmpty) return null;
    final first = c.split(',').first.toLowerCase();
    return switch (first) {
      'matroska' => 'MKV',
      'mov' || 'mp4' || 'm4v' => 'MP4',
      _ => first.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final movie = data.detail;
    final quality = _container(movie.container);
    final genre = movie.genres.isNotEmpty ? movie.genres.first : null;

    return TvBackdrop(
      backdropUrl: movie.backdropUrl,
      posterUrl: movie.posterUrl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(56, 0, 64, 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BackHint(label: 'Back to Library'),
            const SizedBox(height: 26),
            Text(
              quality != null ? 'Film · $quality' : 'Film',
              style: const TextStyle(
                fontFamily: 'Archivo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.8,
                color: ArgosyColors.accent,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 820,
              child: Text(
                movie.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 74,
                  height: 0.96,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2,
                  color: ArgosyColors.cream,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _MetaRow(
              year: movie.year,
              runtime: formatRuntime(movie.durationSeconds),
              rating: movie.rating,
              genre: genre,
            ),
            if (movie.overview != null && movie.overview!.isNotEmpty) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: 660,
                child: Text(
                  movie.overview!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'HankenGrotesk',
                    fontSize: 21,
                    height: 1.55,
                    color: ArgosyColors.soft2,
                  ),
                ),
              ),
            ],
            if (movie.cast.isNotEmpty) ...[
              const SizedBox(height: 20),
              _CastLine(cast: movie.cast),
            ],
            const SizedBox(height: 34),
            _Actions(itemId: movie.id, resumable: _resumable, progress: data.progress),
            if (_resumable && data.progress != null) ...[
              const SizedBox(height: 22),
              _ResumeBar(percent: _percent, progress: data.progress!),
            ],
            if (movie.reviewRequired) ...[
              const SizedBox(height: 18),
              const _ReviewFlag(),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.year,
    required this.runtime,
    required this.rating,
    required this.genre,
  });

  final int? year;
  final String runtime;
  final num? rating;
  final String? genre;

  @override
  Widget build(BuildContext context) {
    const dim = TextStyle(
      fontFamily: 'HankenGrotesk',
      fontSize: 19,
      fontWeight: FontWeight.w600,
      color: ArgosyColors.soft,
    );
    const brass = TextStyle(
      fontFamily: 'HankenGrotesk',
      fontSize: 19,
      fontWeight: FontWeight.w600,
      color: ArgosyColors.accent,
    );
    final parts = <Widget>[];
    void add(Widget w) {
      if (parts.isNotEmpty) {
        parts.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('•', style: TextStyle(color: ArgosyColors.faint)),
        ));
      }
      parts.add(w);
    }

    if (year != null) add(Text('$year', style: dim));
    if (runtime.isNotEmpty && runtime != '—') add(Text(runtime, style: dim));
    if (rating != null && rating! > 0) {
      add(Text('★ ${rating!.toStringAsFixed(1)}', style: brass));
    }
    if (genre != null) add(Text(genre!, style: brass));

    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }
}

/// The 10-foot cast row: a "CAST" label above a comma-joined list of top-billed
/// names (plus the director, for films), scaled for the TV detail screen.
class _CastLine extends StatelessWidget {
  const _CastLine({required this.cast});

  final List<String> cast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 660,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            cast.join(', '),
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
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.itemId,
    required this.resumable,
    required this.progress,
  });

  final String itemId;
  final bool resumable;
  final PlayState? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (resumable) ...[
          TvButton(
            label: 'Resume · ${formatClock(progress!.positionSeconds)}',
            icon: Icons.play_arrow,
            primary: true,
            onSelect: () => openPlayer(context, itemId, resume: true),
          ),
          const SizedBox(width: 18),
          TvButton(
            label: 'Play from start',
            onSelect: () => openPlayer(context, itemId, startOver: true),
          ),
        ] else
          TvButton(
            label: 'Play',
            icon: Icons.play_arrow,
            primary: true,
            onSelect: () => openPlayer(context, itemId),
          ),
        const SizedBox(width: 18),
        TvButton.icon(
          icon: Icons.add,
          label: 'Add to Vault',
          onSelect: () => AddToVaultButton.showFor(context, movieId: itemId),
        ),
      ],
    );
  }
}

class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.percent, required this.progress});

  final double percent;
  final PlayState progress;

  @override
  Widget build(BuildContext context) {
    final remaining = formatRuntime(
      (progress.durationSeconds ?? 0) - progress.positionSeconds,
    );
    return SizedBox(
      width: 540,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 6,
                backgroundColor: ArgosyColors.line3,
                valueColor: const AlwaysStoppedAnimation(ArgosyColors.accent),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${(percent * 100).round()}% watched · $remaining left',
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 15,
              color: ArgosyColors.mute,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "‹ Back" affordance — informational on TV (the remote's BACK key pops);
/// shown so the screen reads like the design.
class _BackHint extends StatelessWidget {
  const _BackHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.chevron_left, size: 22, color: ArgosyColors.dim),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'HankenGrotesk',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ArgosyColors.dim,
          ),
        ),
      ],
    );
  }
}

class _ReviewFlag extends StatelessWidget {
  const _ReviewFlag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ArgosyColors.accentBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ArgosyColors.accentLine),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 18, color: ArgosyColors.accent),
          SizedBox(width: 8),
          Text(
            'Flagged for review',
            style: TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 15,
              color: ArgosyColors.accentSoft,
            ),
          ),
        ],
      ),
    );
  }
}
