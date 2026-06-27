import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../browse/browse_repository.dart';
import '../browse/media_card.dart';
import 'browse_filter.dart';

/// Holds the live library query. The grid watches [libraryResultsProvider],
/// which re-fetches whenever this changes.
class LibraryFilterController extends Notifier<BrowseFilter> {
  @override
  BrowseFilter build() => const BrowseFilter();

  void setScope(BrowseScope scope) => state = state.copyWith(scope: scope);
  void setSort(BrowseSort sort) => state = state.copyWith(sort: sort);

  void toggleGenre(String genre) {
    final genres = state.genres.contains(genre)
        ? (state.genres.where((g) => g != genre).toList())
        : [...state.genres, genre];
    state = state.copyWith(genres: genres);
  }

  void toggleTag(String tag) {
    final v = tag.toLowerCase();
    state = state.copyWith(tag: state.tag == v ? null : v);
  }

  void toggleLabel(String label) =>
      state = state.copyWith(label: state.label == label ? null : label);

  void setWatched(WatchedState? w) =>
      state = state.copyWith(watched: state.watched == w ? null : w);

  void setRatingMin(num? r) =>
      state = state.copyWith(ratingMin: (r ?? 0) > 0 ? r : null);

  void setYearFrom(int? y) => state = state.copyWith(yearFrom: y);
  void setYearTo(int? y) => state = state.copyWith(yearTo: y);

  void clearFacets() => state = state.cleared();

  /// Used by deep links (home genre row "See all").
  void applyGenre(String genre) =>
      state = const BrowseFilter().copyWith(genres: [genre]);
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterController, BrowseFilter>(
        LibraryFilterController.new);

/// The merged, sorted, filtered grid for the current query.
final libraryResultsProvider =
    FutureProvider.autoDispose<List<MediaCard>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return ref.watch(browseRepositoryProvider).browse(filter);
});

/// The profile's custom labels, for the Labels facet (fetched once).
final myLabelsProvider = FutureProvider<List<String>>(
  (ref) async => (await ref.watch(libraryApiProvider).listLabels()) ?? const [],
);

/// The account's most common genre/tag facets (with counts), for the TV
/// library's facet side panel. Mirrors the home genre rows' source so the facet
/// list is identical across surfaces.
final libraryFacetsProvider = FutureProvider<List<Facet>>(
  (ref) async =>
      (await ref.watch(libraryApiProvider).listFacets(limit: 24)) ?? const [],
);
