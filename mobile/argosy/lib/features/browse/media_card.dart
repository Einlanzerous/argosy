import 'package:argosy_api/api.dart';

import '../../util/format.dart';

/// What a card points at — drives both the route and the "Film / Series" label.
enum MediaKind { movie, series }

/// A normalized poster tile shared by the library grid, home rails, search
/// results, and related rows. Collapses the several summary shapes the API
/// returns (movies, series, recent, vault entries) into one render model.
class MediaCard {
  const MediaCard({
    required this.id,
    required this.kind,
    required this.title,
    this.year,
    this.rating,
    this.posterUrl,
    this.backdropUrl,
    this.progress,
    this.subtitleOverride,
  });

  final String id;
  final MediaKind kind;
  final String title;
  final int? year;
  final num? rating;
  final String? posterUrl;
  final String? backdropUrl;

  /// Watch progress in 0..1, or null when not applicable.
  final double? progress;

  /// Used instead of the year·rating line when set (e.g. "S1 · E3" on rails).
  final String? subtitleOverride;

  String get kindLabel => kind == MediaKind.series ? 'Series' : 'Film';

  String? get subtitle => subtitleOverride ?? yearRatingSubtitle(year, rating);

  factory MediaCard.fromSummary(MediaItemSummary m) => MediaCard(
        id: m.id,
        kind: m.kind == 'series' ? MediaKind.series : MediaKind.movie,
        title: formatTitle(m.title),
        year: m.year,
        rating: m.rating,
        posterUrl: m.posterUrl,
        backdropUrl: m.backdropUrl,
      );

  factory MediaCard.fromSeries(SeriesSummary s) => MediaCard(
        id: s.id,
        kind: MediaKind.series,
        title: formatTitle(s.title),
        year: s.year,
        rating: s.rating,
        posterUrl: s.posterUrl,
        backdropUrl: s.backdropUrl,
      );
}
