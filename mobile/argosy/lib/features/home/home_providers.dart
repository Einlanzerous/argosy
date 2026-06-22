import 'package:argosy_api/api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_providers.dart';
import '../../util/format.dart';
import '../browse/browse_repository.dart';
import '../browse/media_card.dart';
import '../library/browse_filter.dart';

/// The hero spotlight at the top of the Bridge.
class HomeHero {
  const HomeHero({
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.kind,
    required this.detailId,
    this.playableId,
    this.posterUrl,
    this.backdropUrl,
    this.percent,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final MediaKind kind;

  /// The id the hero's "Details" tap opens (series id for a resumed episode).
  final String detailId;

  /// The directly-playable item id for the primary Play/Resume button — the
  /// resumed *episode* for a series, the film itself otherwise. Null only if
  /// nothing is playable.
  final String? playableId;
  final String? posterUrl;
  final String? backdropUrl;

  /// 0..1 resume progress, when the hero is a continue-watching item.
  final double? percent;
}

/// A titled row of cards (vault or genre row).
class HomeRow {
  const HomeRow({required this.title, required this.cards, this.seeAllTag});

  final String title;
  final List<MediaCard> cards;

  /// When set, "See all" deep-links the library filtered to this genre.
  final String? seeAllTag;
}

/// Everything the Bridge renders, assembled per the profile's home layout.
class HomeData {
  const HomeData({
    this.hero,
    this.continueRow = const [],
    this.onDeck = const [],
    this.recent = const [],
    this.vaultRows = const [],
    this.genreRows = const [],
  });

  final HomeHero? hero;
  final List<MediaCard> continueRow;
  final List<MediaCard> onDeck;
  final List<MediaCard> recent;
  final List<HomeRow> vaultRows;
  final List<HomeRow> genreRows;

  bool get isEmpty =>
      hero == null && continueRow.isEmpty && onDeck.isEmpty && recent.isEmpty;
}

MediaCard _continueCard(ContinueItem c) => MediaCard(
      id: c.id,
      kind: c.kind == 'series' ? MediaKind.series : MediaKind.movie,
      title: c.seriesTitle ?? c.title,
      subtitleOverride: c.seriesTitle != null
          ? formatTitle(c.title)
          : (c.year != null ? '${c.year}' : null),
      posterUrl: c.posterUrl,
      backdropUrl: c.backdropUrl,
      progress: (c.percent / 100).clamp(0.0, 1.0).toDouble(),
    );

MediaCard _onDeckCard(OnDeckItem o) => MediaCard(
      id: o.seriesId,
      kind: MediaKind.series,
      title: o.seriesTitle,
      subtitleOverride: 'S${o.seasonNumber} · E${o.episodeNumber}',
      posterUrl: o.posterUrl,
      backdropUrl: o.backdropUrl,
    );

MediaCard _vaultEntryCard(VaultEntry e) => MediaCard(
      id: e.id,
      kind: e.kind == VaultEntryKindEnum.series
          ? MediaKind.series
          : MediaKind.movie,
      title: e.title,
      year: e.year,
      rating: e.rating,
      posterUrl: e.posterUrl,
      backdropUrl: e.backdropUrl,
    );

HomeHero? _heroFrom(List<ContinueItem> cont, List<MediaItemSummary> recent) {
  if (cont.isNotEmpty) {
    final r = cont.first;
    return HomeHero(
      eyebrow: 'Continue watching',
      title: r.seriesTitle ?? r.title,
      subtitle: r.seriesTitle != null
          ? formatTitle(r.title)
          : (r.year != null ? '${r.year}' : null),
      kind: r.seriesId != null ? MediaKind.series : MediaKind.movie,
      detailId: r.seriesId ?? r.id,
      // r.id is the resumed item itself (the episode for a series) — playable.
      playableId: r.id,
      posterUrl: r.posterUrl,
      backdropUrl: r.backdropUrl,
      percent: (r.percent / 100).clamp(0.0, 1.0).toDouble(),
    );
  }
  // No resume: spotlight the newest film (a series id isn't directly playable).
  final film = recent.where((i) => i.kind != 'series').firstOrNull;
  if (film != null) {
    return HomeHero(
      eyebrow: 'Featured in the hold',
      title: film.title,
      subtitle: film.year != null ? '${film.year}' : null,
      kind: MediaKind.movie,
      detailId: film.id,
      playableId: film.id,
      posterUrl: film.posterUrl,
      backdropUrl: film.backdropUrl,
    );
  }
  return null;
}

/// Builds the Bridge. The hero + Continue / On Deck / Newly Arrived rows are
/// always loaded; the Vault and genre discovery rows are only fetched when the
/// profile's [UserPreferencesHomeLayoutEnum.homeLayout] is `discovery` (the
/// default) — `focused` keeps the surface lean.
final homeDataProvider = FutureProvider.autoDispose<HomeData>((ref) async {
  final library = ref.watch(libraryApiProvider);
  final auth = ref.watch(authApiProvider);
  final repo = ref.watch(browseRepositoryProvider);

  final results = await Future.wait([
    library.listContinue().then((v) => v ?? const <ContinueItem>[]),
    library.listOnDeck(limit: 12).then((v) => v ?? const <OnDeckItem>[]),
    library.listRecent(limit: 12).then((v) => v ?? const <MediaItemSummary>[]),
    auth.getUserPreferences().then<UserPreferences?>((v) => v).catchError((_) => null),
  ]);

  final cont = results[0] as List<ContinueItem>;
  final onDeck = results[1] as List<OnDeckItem>;
  final recent = results[2] as List<MediaItemSummary>;
  final prefs = results[3] as UserPreferences?;

  final discovery = prefs?.homeLayout != UserPreferencesHomeLayoutEnum.focused;

  var vaultRows = const <HomeRow>[];
  var genreRows = const <HomeRow>[];
  if (discovery) {
    final built = await Future.wait([
      _buildVaultRows(library),
      _buildGenreRows(library, repo),
    ]);
    vaultRows = built[0];
    genreRows = built[1];
  }

  return HomeData(
    hero: _heroFrom(cont, recent),
    continueRow: cont.map(_continueCard).toList(),
    onDeck: onDeck.map(_onDeckCard).toList(),
    recent: recent.map(MediaCard.fromSummary).toList(),
    vaultRows: vaultRows,
    genreRows: genreRows,
  );
});

/// Up to three non-empty vaults as home rows.
Future<List<HomeRow>> _buildVaultRows(LibraryApi api) async {
  final vaults = (await api.listVaults().catchError((_) => <Vault>[]) ?? [])
      .where((v) => v.itemCount > 0)
      .take(3)
      .toList();
  final details = await Future.wait(
    vaults.map((v) => api.getVault(v.id).then<VaultDetail?>((d) => d).catchError((_) => null)),
  );
  return [
    for (final d in details)
      if (d != null)
        HomeRow(
          title: d.name,
          cards: d.items.take(12).map(_vaultEntryCard).toList(),
        ),
  ];
}

/// "Because it's in the hold" rows from the two most common genres,
/// highest-rated first.
Future<List<HomeRow>> _buildGenreRows(
    LibraryApi api, BrowseRepository repo) async {
  final facets = await api.listFacets(limit: 8).catchError((_) => <Facet>[]) ?? [];
  final top = facets
      .where((f) => f.type == FacetTypeEnum.genre)
      .take(2)
      .toList();
  final rows = await Future.wait(top.map((f) async {
    final cards = await repo.browse(BrowseFilter(
      genres: [f.value],
      sort: BrowseSort.rating,
    ));
    return HomeRow(
      title: f.value,
      cards: cards.take(12).toList(),
      seeAllTag: f.value,
    );
  }));
  return rows.where((r) => r.cards.isNotEmpty).toList();
}
