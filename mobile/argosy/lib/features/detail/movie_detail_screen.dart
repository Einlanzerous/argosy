import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../util/format.dart';
import '../../widgets/async_view.dart';
import 'add_to_vault.dart';
import 'detail_providers.dart';
import 'detail_widgets.dart';
import 'label_editor.dart';

/// A film's detail screen: backdrop hero, metadata, genres/tags, your labels,
/// and Play / Resume + Add-to-Vault entry points.
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(movieDetailProvider(itemId));
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
        onRetry: () => ref.invalidate(movieDetailProvider(itemId)),
        builder: (data) => _Body(data: data),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});

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

  @override
  Widget build(BuildContext context) {
    final movie = data.detail;
    final tokens = context.argosy;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailBackdrop(
          // Films lean into the full-screen "hero" look — the backdrop is the
          // pitch; metadata and actions live a scroll below.
          heightFactor: 0.62,
          backdropUrl: movie.backdropUrl,
          posterUrl: movie.posterUrl,
          child: Text(
            movie.title,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetaRow(movie: movie),
              if (movie.overview != null && movie.overview!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  movie.overview!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (movie.cast.isNotEmpty) ...[
                const SizedBox(height: 16),
                CastRow(cast: movie.cast),
              ],
              const SizedBox(height: 16),
              GenreTagChips(genres: movie.genres, tags: movie.tags),
              const SizedBox(height: 20),
              LabelEditor(movieId: movie.id, initial: movie.labels),
              const SizedBox(height: 20),
              _Actions(itemId: movie.id, resumable: _resumable),
              if (_resumable && data.progress != null) ...[
                const SizedBox(height: 14),
                _ResumeBar(percent: _percent, progress: data.progress!),
              ],
              if (movie.reviewRequired) ...[
                const SizedBox(height: 18),
                const ReviewFlag(),
              ],
              SizedBox(height: tokens.radius),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.movie});

  final MediaItemDetail movie;

  @override
  Widget build(BuildContext context) {
    final runtime = formatRuntime(movie.durationSeconds);
    final rating = movie.rating;
    // (text, brass?) parts — score and kind read in brass, the rest dim. Built
    // as spans so the accents sit inline with the dot separators.
    final parts = <(String, bool)>[
      if (movie.year != null) ('${movie.year}', false),
      if (runtime.isNotEmpty && runtime != '—') (runtime, false),
      if (movie.container != null) (movie.container!.toUpperCase(), false),
      if (rating != null && rating > 0)
        ('★ ${rating.toStringAsFixed(1)}', true),
      (movie.kind == 'movie' ? 'Film' : movie.kind, true),
    ];

    final base = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: ArgosyColors.dim);
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(
          const TextSpan(
            text: '   •   ',
            style: TextStyle(color: ArgosyColors.faint),
          ),
        );
      }
      final (text, brass) = parts[i];
      spans.add(
        TextSpan(
          text: text,
          style: brass ? const TextStyle(color: ArgosyColors.accent) : null,
        ),
      );
    }
    return RichText(
      text: TextSpan(style: base, children: spans),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.itemId, required this.resumable});

  final String itemId;
  final bool resumable;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (resumable) ...[
          FilledButton.icon(
            style: brassButtonStyle(context),
            onPressed: () => openPlayer(context, itemId, resume: true),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Resume'),
          ),
          FilledButton.icon(
            style: ghostButtonStyle(context),
            onPressed: () => openPlayer(context, itemId, startOver: true),
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('Start over'),
          ),
        ] else
          FilledButton.icon(
            style: brassButtonStyle(context),
            onPressed: () => openPlayer(context, itemId),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Play'),
          ),
        AddToVaultButton(movieId: itemId),
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
    final tokens = context.argosy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 4,
            backgroundColor: tokens.line2,
            valueColor: AlwaysStoppedAnimation(tokens.progress),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${(percent * 100).round()}% · resume at ${formatClock(progress.positionSeconds)}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
