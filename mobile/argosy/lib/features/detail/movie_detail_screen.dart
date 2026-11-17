import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../theme/breakpoints.dart';
import '../../util/format.dart';
import '../../widgets/action_pill.dart';
import '../../widgets/async_view.dart';
import '../stow/stow_button.dart';
import 'add_to_vault.dart';
import 'detail_providers.dart';
import 'detail_widgets.dart';

/// A film's detail screen: backdrop hero, metadata, genres, and Play / Resume +
/// Add-to-Vault entry points.
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
        leadingWidth: 56,
        leading: const DetailBackButton(),
      ),
      body: AsyncView(
        value: detail,
        keepStale: true,
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
    final expanded = isExpandedWidth(context);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(movie.title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 6),
        _MetaRow(movie: movie),
      ],
    );
    // Actions come before the synopsis, as on a series (ARGY-311): most people
    // open a film to play it.
    final actions = _Actions(
      item: movie,
      resumable: _resumable,
      watched: data.progress?.watched ?? false,
    );
    final rest = <Widget>[
      if (_resumable && data.progress != null) ...[
        const SizedBox(height: 14),
        _ResumeBar(percent: _percent, progress: data.progress!),
      ],
      if (movie.overview != null && movie.overview!.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(movie.overview!, style: Theme.of(context).textTheme.bodyMedium),
      ],
      if (movie.cast.isNotEmpty) ...[
        const SizedBox(height: 16),
        CastRow(cast: movie.cast),
      ],
      if (movie.genres.isNotEmpty) ...[
        const SizedBox(height: 16),
        GenreTagChips(genres: movie.genres),
      ],
      if (movie.reviewRequired) ...[
        const SizedBox(height: 18),
        const ReviewFlag(),
      ],
    ];

    if (expanded) {
      return FullBleedDetail(
        key: const ValueKey('movie-expanded'),
        backdropUrl: movie.backdropUrl,
        posterUrl: movie.posterUrl,
        details: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [titleBlock, const SizedBox(height: 16), actions, ...rest],
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        DetailBackdrop(
          // Films lean into the full-screen "hero" look; the title and meta sit
          // on the art, with the actions straight below.
          heightFactor: 0.56,
          backdropUrl: movie.backdropUrl,
          posterUrl: movie.posterUrl,
          child: titleBlock,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [actions, ...rest, SizedBox(height: tokens.radius)],
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
      if (yearLabel(movie.year) case final year?) (year, false),
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

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.item,
    required this.resumable,
    required this.watched,
  });

  final MediaItemDetail item;
  final bool resumable;
  final bool watched;

  String get itemId => item.id;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Play/Resume takes the row; Vault, Stow and Watched follow as 50dp
    // squares, the same family as a series' action row (ARGY-311).
    final row = Row(
      key: const ValueKey('movie-actions'),
      children: [
        Expanded(
          child: FilledButton.icon(
            style: brassButtonStyle(
              context,
              minimumSize: const Size(0, ActionPill.squareSize),
            ),
            onPressed: () => openPlayerThenRefresh(
              context,
              movieDetailProvider(itemId),
              itemId,
              resume: resumable,
            ),
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(resumable ? 'Resume' : 'Play'),
          ),
        ),
        const SizedBox(width: _gap),
        AddToVaultButton(movieId: itemId, iconOnly: true),
        const SizedBox(width: _gap),
        StowButton(item: item, square: true),
        const SizedBox(width: _gap),
        WatchedButton(
          square: true,
          watched: watched,
          onSet: (next) async {
            await ref
                .read(libraryApiProvider)
                .setWatched(itemId, WatchedUpdate(watched: next));
            // Reflect the new watched/Resume state (and Continue Watching).
            ref.invalidate(movieDetailProvider(itemId));
          },
        ),
      ],
    );
    if (!resumable) return row;
    // "Start over" only exists alongside Resume, so it rides directly under it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const SizedBox(height: _gap),
        FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => openPlayerThenRefresh(
            context,
            movieDetailProvider(itemId),
            itemId,
            startOver: true,
          ),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Play from start'),
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
