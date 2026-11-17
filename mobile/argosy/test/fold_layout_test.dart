// The folded/unfolded design pass (ARGY-308): Bridge, Manifest, Series and the
// app shell, pumped at a regular phone width and at a foldable's inner-screen
// width. The compact layout is the everyday one; expanded adds the rail and the
// wide layouts on top of it.

import 'dart:io';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/browse/media_card.dart';
import 'package:argosy/features/detail/series_detail_screen.dart';
import 'package:argosy/features/home/home_providers.dart';
import 'package:argosy/features/home/home_screen.dart';
import 'package:argosy/features/library/library_controller.dart';
import 'package:argosy/features/library/library_screen.dart';
import 'package:argosy/features/stow/stow_controller.dart';
import 'package:argosy/features/stow/stow_service.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/router/scaffold_with_nav.dart';
import 'package:argosy/theme/argosy_theme.dart';
import 'package:argosy/theme/breakpoints.dart';
import 'package:argosy/widgets/device_pill.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _compact = Size(412, 915);
const _expanded = Size(900, 700);

class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  @override
  Future<SeriesDetail?> getSeries(
    String id, {
    Future<void>? abortTrigger,
  }) async => SeriesDetail(
    id: 'series-1',
    title: 'Lanternfish Harbour',
    overview: 'A harbour town and the people who keep its lights on.',
    cast: const ['A. Actor', 'B. Actress'],
    seasons: [
      for (final n in [1, 2])
        SeasonSummary(
          id: 'season-$n',
          seasonNumber: n,
          episodes: [
            for (final e in [1, 2])
              EpisodeSummary(
                id: 's${n}e$e',
                episodeNumber: e,
                title: 'Episode $e',
                overview: 'The tide turns in episode $e.',
                mediaItemId: 'm$n$e',
                watched: n == 1 && e == 1,
              ),
          ],
        ),
    ],
  );
}

void main() {
  late Directory root;
  late StowStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-fold');
    store = StowStore(root: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget home, {
    List overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stowStoreProvider.overrideWithValue(store),
          stowEngineProvider.overrideWithValue(
            LocalStowEngine(store: store, connect: () async => throw 'unused'),
          ),
          libraryApiProvider.overrideWithValue(_Library()),
          ...overrides,
        ],
        child: MaterialApp(theme: buildArgosyTheme(), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the expanded breakpoint is the Material medium class, 600dp', () {
    expect(kExpandedWidth, 600);
  });

  group('shell', () {
    Widget shell() {
      final router = GoRouter(
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, s) => ScaffoldWithNav(navigationShell: s),
            branches: [
              for (final p in ['/a', '/b', '/c'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: p,
                      builder: (_, _) => Center(child: Text('page $p')),
                    ),
                  ],
                ),
            ],
          ),
        ],
        initialLocation: '/a',
      );
      return MaterialApp.router(
        theme: buildArgosyTheme(),
        routerConfig: router,
      );
    }

    testWidgets('compact keeps the bottom bar', (tester) async {
      tester.view.physicalSize = _compact;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('expanded swaps it for an 84dp labelled rail', (tester) async {
      tester.view.physicalSize = _expanded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const ValueKey('nav-rail')), findsOneWidget);
      expect(tester.getSize(find.byType(NavigationRail)).width, 84);
      for (final label in ['Bridge', 'Manifest', 'Search']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Manifest'));
      await tester.pumpAndSettle();
      expect(find.text('page /b'), findsOneWidget);
    });
  });

  group('series', () {
    Future<void> pumpSeries(WidgetTester tester, Size size) =>
        pumpAt(tester, size, const SeriesDetailScreen(seriesId: 'series-1'));

    testWidgets('compact: scope actions on the season header as icons', (
      tester,
    ) async {
      await pumpSeries(tester, _compact);

      // Wide Resume with the Vault as an icon beside it.
      final resume = find.widgetWithText(FilledButton, 'Resume S1 Ep 2');
      expect(resume, findsOneWidget);
      expect(tester.getSize(resume).width, greaterThan(250));
      expect(find.byTooltip('Add to Vault'), findsOneWidget);
      expect(find.text('Add to Vault'), findsNothing);

      // Show-level: Mark series watched is a 50dp square in the top row,
      // beside Vault, level with Resume.
      final seriesWatched = find.byTooltip('Mark series watched');
      expect(seriesWatched, findsOneWidget);
      expect(tester.getSize(seriesWatched), const Size(50, 50));
      expect(
        tester.getCenter(seriesWatched).dy,
        closeTo(tester.getCenter(resume).dy, 1),
      );
      expect(
        tester.getCenter(seriesWatched).dx,
        greaterThan(tester.getCenter(find.byTooltip('Add to Vault')).dx),
      );

      // Season header: picker + count on the left, exactly two icon circles
      // (Watched, Stow) on the same row at the right.
      final picker = find.byKey(const ValueKey('season-picker'));
      expect(picker, findsOneWidget);
      expect(find.text('1 of 2 watched'), findsOneWidget);
      final markSeason = find.byTooltip('Mark season watched');
      final stow = find.byTooltip('Stow season');
      expect(markSeason, findsOneWidget);
      expect(stow, findsOneWidget);
      expect(tester.getSize(markSeason), const Size(44, 44));
      expect(tester.getSize(stow), const Size(44, 44));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('season-actions')),
          matching: find.byType(IconButton),
        ),
        findsNWidgets(2),
      );
      expect(
        (tester.getCenter(markSeason).dy - tester.getCenter(picker).dy).abs(),
        lessThan(24),
        reason: 'same row as the season title',
      );
      expect(tester.getCenter(markSeason).dx, greaterThan(300));
      expect(find.text('Mark season watched'), findsNothing);
      expect(find.text('Stow season'), findsNothing);

      // Back is a 40dp rounded square.
      expect(
        tester.getSize(find.byKey(const ValueKey('series-back'))),
        const Size(40, 40),
      );

      // Single column: no left pane.
      expect(find.byKey(const ValueKey('series-left-pane')), findsNothing);
    });

    testWidgets('expanded: two panes, labelled pills on the season panel', (
      tester,
    ) async {
      await pumpSeries(tester, _expanded);

      final left = find.byKey(const ValueKey('series-left-pane'));
      expect(left, findsOneWidget);
      expect(tester.getSize(left).width, 340);
      expect(find.byKey(const ValueKey('series-season-pane')), findsOneWidget);

      // Title + actions + synopsis + cast on the left.
      for (final t in [
        find.text('Lanternfish Harbour'),
        find.textContaining('A harbour town'),
        find.text('CAST'),
        find.widgetWithText(FilledButton, 'Resume S1 Ep 2'),
        find.byTooltip('Add to Vault'),
        find.byTooltip('Mark series watched'),
      ]) {
        expect(
          tester.getTopLeft(t).dx,
          lessThan(340),
          reason: 'left of the divider',
        );
      }

      // Season panel on the right: two labelled pills on the title row (they
      // must not wrap), then the episode rows.
      final markWatched = find.text('Mark watched');
      final stow = find.text('Stow');
      expect(markWatched, findsOneWidget);
      expect(stow, findsOneWidget);
      expect(
        tester.getCenter(markWatched).dy,
        closeTo(tester.getCenter(stow).dy, 1),
      );
      expect(
        (tester.getCenter(markWatched).dy -
                tester
                    .getCenter(find.byKey(const ValueKey('season-picker')))
                    .dy)
            .abs(),
        lessThan(24),
        reason: 'same row as the season title',
      );
      for (final t in [
        markWatched,
        stow,
        find.text('Episode 1'),
        find.textContaining('The tide turns in episode 1'),
      ]) {
        expect(tester.getTopLeft(t).dx, greaterThan(340));
      }
    });
  });

  group('manifest', () {
    final cards = [
      for (var i = 0; i < 14; i++)
        MediaCard(id: 'c$i', kind: MediaKind.movie, title: 'Title $i'),
    ];
    final override = libraryResultsProvider.overrideWith((ref) async => cards);

    testWidgets('compact: two-row header, no search bar or eyebrow', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _compact,
        const LibraryScreen(),
        overrides: [override],
      );
      expect(find.text('Manifest'), findsOneWidget);
      // The count follows the title on its baseline; sort stays on the right.
      expect(find.text('14'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('14')).dx,
        lessThan(tester.getTopLeft(find.text('Recently Added')).dx),
      );
      expect(
        tester.getBottomLeft(find.text('14')).dy,
        closeTo(tester.getBottomLeft(find.text('Manifest')).dy, 8),
      );
      expect(
        tester.getTopLeft(find.text('14')).dx -
            tester.getTopRight(find.text('Manifest')).dx,
        lessThan(24),
      );
      expect(find.text('Search the Manifest…'), findsNothing);
      expect(find.text('THE MANIFEST'), findsNothing);
      for (final chip in ['All', 'Movies', 'Shows']) {
        expect(find.text(chip), findsOneWidget);
      }
      // Filters is an icon on a phone.
      expect(
        find.byKey(const ValueKey('manifest-filter-icon')),
        findsOneWidget,
      );
      expect(find.text('Filters'), findsNothing);
      // The chips are on the second row, under the title.
      expect(
        tester.getTopLeft(find.text('All')).dy,
        greaterThan(tester.getTopLeft(find.text('Manifest')).dy),
      );
    });

    testWidgets('expanded: one header row, labelled Filters, 6-column grid', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(1200, 800),
        const LibraryScreen(),
        overrides: [override],
      );
      expect(find.text('Search the Manifest…'), findsNothing);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.byKey(const ValueKey('manifest-filter-icon')), findsNothing);
      // Title, count, chips and sort share one row.
      final y = tester.getCenter(find.text('Manifest')).dy;
      for (final t in [find.text('14 titles'), find.text('All')]) {
        expect((tester.getCenter(t).dy - y).abs(), lessThan(20));
      }
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 6);
    });
  });

  group('bridge', () {
    final home = HomeData(
      hero: const HomeHero(
        eyebrow: 'Continue watching',
        title: 'Brackwater',
        subtitle: 'S1 · E3',
        kind: MediaKind.series,
        detailId: 'series-1',
        playableId: 'm13',
        percent: 0.4,
        remainingLabel: '20m left',
        deviceLabel: 'Sony Bravia',
      ),
      continueRow: [
        for (var i = 0; i < 4; i++)
          ContinueEntry(
            id: 'c$i',
            kind: MediaKind.movie,
            title: 'Resume $i',
            progress: 0.3,
          ),
      ],
    );
    final override = homeDataProvider.overrideWith((ref) async => home);

    testWidgets('compact: solid pills, full-width resume, continue strip', (
      tester,
    ) async {
      await pumpAt(tester, _compact, const HomeScreen(), overrides: [override]);
      expect(find.byKey(const ValueKey('hero-eyebrow')), findsOneWidget);
      expect(find.text('CONTINUE WATCHING'), findsOneWidget);
      expect(find.byKey(const ValueKey('continue-grid')), findsNothing);
      final resume = find.byKey(const ValueKey('hero-resume'));
      expect(tester.getSize(resume).width, greaterThan(200));
      expect(tester.getSize(resume).height, 48);
      // No device pill above the bar; the note is "from / <device>" beside
      // Resume, and the remaining time sits right of the episode line.
      expect(find.byType(DevicePill), findsNothing);
      expect(find.text('from'), findsOneWidget);
      expect(find.text('Sony Bravia'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Sony Bravia')).dx,
        greaterThan(tester.getTopRight(resume).dx),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('hero-remaining'))).dx,
        greaterThanOrEqualTo(tester.getTopRight(find.text('S1 · E3')).dx),
      );
      // Right-aligned: its right edge is the hero text column's.
      expect(
        tester.getTopRight(find.byKey(const ValueKey('hero-remaining'))).dx,
        closeTo(tester.getTopRight(resume).dx + 12 + 110, 40),
      );
      expect(find.text('Argosy'), findsOneWidget);
    });

    testWidgets('expanded: capped hero, fixed Resume, 4-up continue grid', (
      tester,
    ) async {
      await pumpAt(
        tester,
        _expanded,
        const HomeScreen(),
        overrides: [override],
      );
      final resume = find.byKey(const ValueKey('hero-resume'));
      expect(tester.getSize(resume).width, inInclusiveRange(120, 300));
      // "from <device>" inline to its right; progress row is bar + label.
      expect(find.text('from Sony Bravia'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('from Sony Bravia')).dx,
        greaterThan(tester.getTopRight(resume).dx),
      );
      expect(find.byKey(const ValueKey('hero-remaining')), findsOneWidget);
      // Only the avatar remains in the app bar: the rail carries the brand.
      expect(find.text('Argosy'), findsNothing);

      // Hero is capped at 300dp: the grid's top sits just below it.
      final grid = find.byKey(const ValueKey('continue-grid'));
      expect(grid, findsOneWidget);
      expect(tester.getTopLeft(grid).dy, lessThan(300 + 160));

      // Four cards on one row.
      final tops = {
        for (var i = 0; i < 4; i++)
          tester.getTopLeft(find.text('Resume $i')).dy.round(),
      };
      expect(tops.length, 1);
    });
  });
}
