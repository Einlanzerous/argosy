// Home's genre rows are decoration: when a library request behind one fails,
// Home must still load with the rest of its rows (ARGY-251 made the shared
// BrowseRepository.browse throw instead of swallowing).

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/browse/browse_repository.dart';
import 'package:argosy/features/home/home_providers.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryApi extends LibraryApi {
  @override
  Future<List<ContinueItem>?> listContinue({Future<void>? abortTrigger}) async =>
      const [];

  @override
  Future<List<OnDeckItem>?> listOnDeck({
    int? limit,
    Future<void>? abortTrigger,
  }) async => const [];

  @override
  Future<List<MediaItemSummary>?> listRecent({
    int? limit,
    Future<void>? abortTrigger,
  }) async => const [];

  @override
  Future<List<Vault>?> listVaults({Future<void>? abortTrigger}) async =>
      const [];

  @override
  Future<List<Facet>?> listFacets({
    int? limit,
    Future<void>? abortTrigger,
  }) async => [Facet(type: FacetTypeEnum.genre, value: 'Drama', count: 3)];

  @override
  Future<List<ModelLibrary>?> listLibraries({
    Future<void>? abortTrigger,
  }) async => [ModelLibrary(id: 'l1', name: 'l1', kind: 'mixed')];

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
  }) async => throw ApiException(503, 'down');
}

class _FakeAuthApi extends AuthApi {
  @override
  Future<UserPreferences?> getUserPreferences({
    Future<void>? abortTrigger,
  }) async => null;
}

void main() {
  test('a failing genre row does not fail Home', () async {
    final api = _FakeLibraryApi();
    final container = ProviderContainer(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        authApiProvider.overrideWithValue(_FakeAuthApi()),
        browseRepositoryProvider.overrideWithValue(BrowseRepository(api)),
      ],
    );
    addTearDown(container.dispose);

    final data = await container.read(homeDataProvider.future);

    expect(data.genreRows, isEmpty);
  });
}
