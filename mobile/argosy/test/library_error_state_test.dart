// A failed Library request must read as an error with Retry, never as an empty
// grid (ARGY-251; web did the same in ARGY-237). A library that genuinely has
// no titles still gets the empty state. Partial failure is all-or-nothing: one
// library of several failing fails the whole load.

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/browse/browse_repository.dart';
import 'package:argosy/features/library/browse_filter.dart';
import 'package:argosy/features/library/library_controller.dart';
import 'package:argosy/features/library/library_screen.dart';
import 'package:argosy/features/library/tv/tv_library_screen.dart';
import 'package:argosy/theme/argosy_theme.dart';
import 'package:argosy/theme/argosy_theme_tv.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryApi extends LibraryApi {
  _FakeLibraryApi({required this.libs, this.failMovies = const {}});

  final List<ModelLibrary> libs;

  /// Library ids whose movie request answers 503.
  final Set<String> failMovies;

  int movieCalls = 0;

  @override
  Future<List<ModelLibrary>?> listLibraries({
    Future<void>? abortTrigger,
  }) async => libs;

  @override
  Future<MediaItemPage?> listMovies(
    String libraryId, {
    int? limit,
    int? offset,
    String? sort,
    List<String>? genre,
    num? ratingMin,
    String? watched,
    int? yearFrom,
    int? yearTo,
    Future<void>? abortTrigger,
  }) async {
    movieCalls++;
    if (failMovies.contains(libraryId)) throw ApiException(503, 'down');
    return MediaItemPage(total: 0, limit: 200, offset: 0);
  }

  @override
  Future<SeriesPage?> listSeries(
    String libraryId, {
    int? limit,
    int? offset,
    String? sort,
    List<String>? genre,
    num? ratingMin,
    String? watched,
    int? yearFrom,
    int? yearTo,
    Future<void>? abortTrigger,
  }) async => SeriesPage(total: 0, limit: 200, offset: 0);
}

ModelLibrary _lib(String id) => ModelLibrary(id: id, name: id, kind: 'mixed');

Future<void> _pump(
  WidgetTester tester,
  _FakeLibraryApi api,
  Widget screen, {
  required bool tv,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        browseRepositoryProvider.overrideWithValue(BrowseRepository(api)),
        libraryFacetsProvider.overrideWith((ref) async => const <Facet>[]),
      ],
      child: MaterialApp(
        theme: tv ? buildArgosyThemeTv() : buildArgosyTheme(),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BrowseRepository.browse', () {
    test('a failing listMovies throws instead of returning an empty list',
        () async {
      final repo = BrowseRepository(
        _FakeLibraryApi(libs: [_lib('a')], failMovies: {'a'}),
      );
      await expectLater(
        repo.browse(const BrowseFilter()),
        throwsA(isA<ApiFailure>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
    });

    test('one of several libraries failing fails the whole load', () async {
      final repo = BrowseRepository(
        _FakeLibraryApi(libs: [_lib('a'), _lib('b')], failMovies: {'b'}),
      );
      await expectLater(
        repo.browse(const BrowseFilter()),
        throwsA(isA<ApiFailure>()),
      );
    });

    test('libraries that answer with no titles are an empty list', () async {
      final repo = BrowseRepository(_FakeLibraryApi(libs: [_lib('a')]));
      expect(await repo.browse(const BrowseFilter()), isEmpty);
    });
  });

  final screens = <String, Widget Function()>{
    'phone': () => const LibraryScreen(),
    'TV': () => const TvLibraryScreen(),
  };

  for (final entry in screens.entries) {
    group('${entry.key} Library', () {
      testWidgets('a failed request shows an error with Retry, not empty',
          (tester) async {
        final api = _FakeLibraryApi(libs: [_lib('a')], failMovies: {'a'});
        await _pump(tester, api, entry.value(), tv: entry.key == 'TV');

        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('The hold is empty'), findsNothing);

        final before = api.movieCalls;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(api.movieCalls, greaterThan(before),
            reason: 'Retry must re-run the request');
      });

      testWidgets('a genuinely empty library shows the empty state, no Retry',
          (tester) async {
        await _pump(tester, _FakeLibraryApi(libs: [_lib('a')]), entry.value(), tv: entry.key == 'TV');

        expect(find.text('The hold is empty'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });
    });
  }
}
