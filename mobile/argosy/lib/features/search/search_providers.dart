import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../browse/browse_repository.dart';
import '../browse/media_card.dart';

typedef SearchGroups = ({List<MediaCard> films, List<MediaCard> series});

/// The current (debounced) search query. The screen writes it after the
/// typeahead settles; the results provider reacts.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final searchQueryProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// Grouped films/series for the active query. Below two characters it stays
/// empty (no point hitting the server on a single keystroke).
final searchResultsProvider =
    FutureProvider.autoDispose<SearchGroups>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return (films: <MediaCard>[], series: <MediaCard>[]);

  final res = await ref.watch(browseRepositoryProvider).search(query);
  return (
    films: res.movies.map(MediaCard.fromSummary).toList(),
    series: res.series.map(MediaCard.fromSeries).toList(),
  );
});
