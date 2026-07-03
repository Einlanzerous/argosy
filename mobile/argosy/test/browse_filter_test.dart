import 'package:argosy/features/library/browse_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrowseFilter', () {
    test('activeCount counts each engaged facet once', () {
      const f = BrowseFilter(
        genres: ['Action', 'Drama'],
        watched: WatchedState.unwatched,
        ratingMin: 7,
        yearFrom: 1990,
      );
      // 2 genres + watched + rating + year-range = 5
      expect(f.activeCount, 5);
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
      const f = BrowseFilter(
          ratingMin: 7, watched: WatchedState.watched);
      final cleared = f.copyWith(ratingMin: null, watched: null);
      expect(cleared.ratingMin, isNull);
      expect(cleared.watched, isNull);
    });

    test('copyWith preserves untouched facets', () {
      const f = BrowseFilter(genres: ['Action']);
      final next = f.copyWith(sort: BrowseSort.title);
      expect(next.genres, ['Action']);
      expect(next.sort, BrowseSort.title);
    });

    test('cleared() drops facets but keeps scope + sort', () {
      const f = BrowseFilter(
        scope: BrowseScope.movies,
        sort: BrowseSort.rating,
        genres: ['Action'],
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
