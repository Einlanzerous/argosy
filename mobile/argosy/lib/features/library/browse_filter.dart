import 'package:flutter/foundation.dart';

/// Which kinds the library grid shows.
enum BrowseScope { all, movies, series }

/// Sort orders. `added` is film-only; series fall back to `title` for it.
enum BrowseSort { added, title, year, rating }

extension BrowseSortX on BrowseSort {
  /// Wire value for the `sort` query param.
  String get wire => switch (this) {
        BrowseSort.added => 'added',
        BrowseSort.title => 'title',
        BrowseSort.year => 'year',
        BrowseSort.rating => 'rating',
      };

  String get label => switch (this) {
        BrowseSort.added => 'Recently Added',
        BrowseSort.title => 'Title',
        BrowseSort.year => 'Year',
        BrowseSort.rating => 'Rating',
      };
}

/// Watched-state facet.
enum WatchedState { unwatched, inProgress, watched }

extension WatchedStateX on WatchedState {
  String get wire => switch (this) {
        WatchedState.unwatched => 'unwatched',
        WatchedState.inProgress => 'in_progress',
        WatchedState.watched => 'watched',
      };

  String get label => switch (this) {
        WatchedState.unwatched => 'Unwatched',
        WatchedState.inProgress => 'In progress',
        WatchedState.watched => 'Watched',
      };
}

/// The genres Stevedore derives, mirrored from the web manifest so the facet
/// list is identical across clients.
const kGenres = <String>[
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'Horror',
  'Mystery',
  'Romance',
  'Sci-Fi',
  'Thriller',
  'War',
  'Western',
];

/// Immutable browse query: scope + sort + facets. Lives in the library
/// controller's state; the grid reloads whenever it changes.
@immutable
class BrowseFilter {
  const BrowseFilter({
    this.scope = BrowseScope.all,
    this.sort = BrowseSort.added,
    this.genres = const [],
    this.ratingMin,
    this.watched,
    this.yearFrom,
    this.yearTo,
  });

  final BrowseScope scope;
  final BrowseSort sort;
  final List<String> genres;
  final num? ratingMin;
  final WatchedState? watched;
  final int? yearFrom;
  final int? yearTo;

  int get activeCount =>
      genres.length +
      (watched != null ? 1 : 0) +
      ((ratingMin ?? 0) > 0 ? 1 : 0) +
      (yearFrom != null || yearTo != null ? 1 : 0);

  bool get hasFacets => activeCount > 0;

  BrowseFilter copyWith({
    BrowseScope? scope,
    BrowseSort? sort,
    List<String>? genres,
    Object? ratingMin = _unset,
    Object? watched = _unset,
    Object? yearFrom = _unset,
    Object? yearTo = _unset,
  }) {
    return BrowseFilter(
      scope: scope ?? this.scope,
      sort: sort ?? this.sort,
      genres: genres ?? this.genres,
      ratingMin: ratingMin == _unset ? this.ratingMin : ratingMin as num?,
      watched: watched == _unset ? this.watched : watched as WatchedState?,
      yearFrom: yearFrom == _unset ? this.yearFrom : yearFrom as int?,
      yearTo: yearTo == _unset ? this.yearTo : yearTo as int?,
    );
  }

  /// Resets the facets but keeps scope + sort.
  BrowseFilter cleared() => BrowseFilter(scope: scope, sort: sort);
}

const _unset = Object();
