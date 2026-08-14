import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../router/app_router.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../util/format.dart';
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
              GenreTagChips(genres: movie.genres),
              const SizedBox(height: 20),
              _Actions(
                item: movie,
                resumable: _resumable,
                watched: data.progress?.watched ?? false,
              ),
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

  /// Gap between buttons, matched to the old Wrap's spacing.
  static const double _gap = 12;

  /// Play/Resume carries more weight than the actions beside it, so it takes a
  /// larger share of the row rather than merely being first in a line of
  /// equals.
  static const int _primaryFlex = 3;
  static const int _secondaryFlex = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = FilledButton.icon(
      style: brassButtonStyle(context),
      onPressed: () => openPlayer(context, itemId, resume: resumable),
      icon: const Icon(Icons.play_arrow, size: 20),
      label: Text(resumable ? 'Resume' : 'Play'),
    );

    // Ordered by how often they're reached. "Start over" only exists alongside
    // Resume, and sits first so it stays next to the play action it qualifies.
    final secondary = <Widget>[
      if (resumable)
        FilledButton.icon(
          style: ghostButtonStyle(context),
          onPressed: () => openPlayer(context, itemId, startOver: true),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('Start over'),
        ),
      StowButton(item: item),
      AddToVaultButton(movieId: itemId),
      WatchedButton(
        watched: watched,
        onSet: (next) async {
          await ref
              .read(libraryApiProvider)
              .setWatched(itemId, WatchedUpdate(watched: next));
          // Reflect the new watched/Resume state (and Continue Watching).
          ref.invalidate(movieDetailProvider(itemId));
        },
      ),
    ];

    // Landscape has the width for one row; portrait pairs them up. Either way
    // the buttons fill the row instead of sizing to their labels, so the block
    // reads as a deliberate grid rather than as text of varying length — which
    // is what the free-flowing Wrap produced (3 buttons then a lonely 4th).
    if (MediaQuery.orientationOf(context) == Orientation.landscape) {
      return Row(
        children: [
          Expanded(flex: _primaryFlex, child: primary),
          for (final action in secondary) ...[
            const SizedBox(width: _gap),
            Expanded(flex: _secondaryFlex, child: action),
          ],
        ],
      );
    }

    final rows = <Widget>[
      Row(
        children: [
          Expanded(flex: _primaryFlex, child: primary),
          const SizedBox(width: _gap),
          Expanded(flex: _secondaryFlex, child: secondary.first),
        ],
      ),
    ];
    final rest = secondary.skip(1).toList();
    for (var i = 0; i < rest.length; i += 2) {
      rows.add(const SizedBox(height: _gap));
      // A trailing odd button spans the full width. With Resume in play there
      // are five actions, and a half-width button alone on the last row is the
      // ragged look this layout exists to avoid.
      rows.add(
        i + 1 < rest.length
            ? Row(
                children: [
                  Expanded(child: rest[i]),
                  const SizedBox(width: _gap),
                  Expanded(child: rest[i + 1]),
                ],
              )
            : rest[i],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
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
