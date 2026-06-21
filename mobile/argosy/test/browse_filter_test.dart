import 'package:argosy/features/library/browse_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowseFilter', () {
    test('activeCount counts each engaged facet once', () {
      const f = BrowseFilter(
        genres: ['Action', 'Drama'],
        tag: 'anime',
        watched: WatchedState.unwatched,
        ratingMin: 7,
        yearFrom: 1990,
      );
      // 2 genres + tag + watched + rating + year-range = 6
      expect(f.activeCount, 6);
      expect(f.hasFacets, isTrue);
    });

    test('a year range (from and/or to) counts as a single facet', () {
      expect(const BrowseFilter(yearFrom: 1990, yearTo: 2000).activeCount, 1);
      expect(const BrowseFilter(yearTo: 2000).activeCount, 1);
    });

    test('a zero rating floor is not an active facet', () {
      expect(const BrowseFilter(ratingMin: 0).activeCount, 0);
    });

    test('copyWith can null a facet out via sentinel', () {
      const f = BrowseFilter(tag: 'anime', watched: WatchedState.watched);
      final cleared = f.copyWith(tag: null, watched: null);
      expect(cleared.tag, isNull);
      expect(cleared.watched, isNull);
    });

    test('copyWith preserves untouched facets', () {
      const f = BrowseFilter(tag: 'anime', genres: ['Action']);
      final next = f.copyWith(sort: BrowseSort.title);
      expect(next.tag, 'anime');
      expect(next.genres, ['Action']);
      expect(next.sort, BrowseSort.title);
    });

    test('cleared() drops facets but keeps scope + sort', () {
      const f = BrowseFilter(
        scope: BrowseScope.movies,
        sort: BrowseSort.rating,
        genres: ['Action'],
        tag: 'anime',
      );
      final c = f.cleared();
      expect(c.scope, BrowseScope.movies);
      expect(c.sort, BrowseSort.rating);
      expect(c.hasFacets, isFalse);
    });

    test('sort wire values match the API contract', () {
      expect(BrowseSort.added.wire, 'added');
      expect(BrowseSort.rating.wire, 'rating');
      expect(WatchedState.inProgress.wire, 'in_progress');
    });
  });
}
