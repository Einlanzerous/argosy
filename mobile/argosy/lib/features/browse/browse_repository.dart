import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../library/browse_filter.dart';
import 'media_card.dart';

/// Data access for the browse surfaces. Wraps [LibraryApi], fans the
/// per-library movie/series endpoints out across every library and merges the
/// pages (the API paginates per library; the grid wants one combined list),
/// then normalizes everything to [MediaCard].
class BrowseRepository {
  BrowseRepository(this._api);

  final LibraryApi _api;

  static const _pageLimit = 200;

  Future<List<ModelLibrary>> libraries() async =>
      (await _api.listLibraries()) ?? const [];

  /// Movies + series across all libraries for the given [filter], merged and
  /// re-sorted client-side so ordering is consistent across libraries.
  Future<List<MediaCard>> browse(BrowseFilter filter) async {
    final libs = await libraries();
    final cards = <MediaCard>[];

    if (filter.scope != BrowseScope.series) {
      final pages = await Future.wait(
        libs.map((l) => _api
            .listMovies(
              l.id,
              limit: _pageLimit,
              sort: filter.sort.wire,
              genre: filter.genres.isEmpty ? null : filter.genres,
              ratingMin: filter.ratingMin,
              watched: filter.watched?.wire,
              yearFrom: filter.yearFrom,
              yearTo: filter.yearTo,
            )
            .then((p) => p?.items ?? const <MediaItemSummary>[])
            .catchError((_) => const <MediaItemSummary>[])),
      );
      for (final page in pages) {
        cards.addAll(page.map(MediaCard.fromSummary));
      }
    }

    if (filter.scope != BrowseScope.movies) {
      // Series have no "added" sort; fall back to title for it.
      final seriesSort =
          filter.sort == BrowseSort.added ? BrowseSort.title : filter.sort;
      final pages = await Future.wait(
        libs.map((l) => _api
            .listSeries(
              l.id,
              limit: _pageLimit,
              sort: seriesSort.wire,
              genre: filter.genres.isEmpty ? null : filter.genres,
              ratingMin: filter.ratingMin,
              watched: filter.watched?.wire,
              yearFrom: filter.yearFrom,
              yearTo: filter.yearTo,
            )
            .then((p) => p?.items ?? const <SeriesSummary>[])
            .catchError((_) => const <SeriesSummary>[])),
      );
      for (final page in pages) {
        cards.addAll(page.map(MediaCard.fromSeries));
      }
    }

    _sort(cards, filter.sort);
    return cards;
  }

  /// Re-applies the chosen sort across the merged (multi-library) list. The
  /// per-library response is already sorted; this restores a single global
  /// order. `added` can't be reconstructed client-side (no timestamp in the
  /// summary), so it keeps the server's per-library append order.
  static void _sort(List<MediaCard> cards, BrowseSort sort) {
    switch (sort) {
      case BrowseSort.title:
        cards.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case BrowseSort.year:
        cards.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case BrowseSort.rating:
        cards.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      case BrowseSort.added:
        break;
    }
  }

  /// Grouped typeahead search.
  Future<SearchResults> search(String query, {int limit = 20}) async {
    final res = await _api.search(query, limit: limit);
    return res ?? SearchResults();
  }
}

final browseRepositoryProvider = Provider<BrowseRepository>(
  (ref) => BrowseRepository(ref.watch(libraryApiProvider)),
);
