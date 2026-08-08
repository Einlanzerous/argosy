// The brass focus ring must not be clipped by the scroller it sits in
// (ARGY-184).
//
// TvFocusable paints the ring outside its child's box and then scales the lot,
// so it reaches `tvFocusClearance` past the content on every side. Scrollers
// clip at their viewport, so a rail or list that doesn't reserve that room
// slices the ring off — the tiles at the edges lose their sides, and every tile
// in a rail loses its top.
//
// These assert the geometry rather than a screenshot: they run at the real
// 1920×1080 TvStage size and compare the ring's reach against the viewport that
// would cut it, which is what the eye is reporting on the panel.

import 'package:argosy/features/browse/media_card.dart';
import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/tv/tv_series_screen.dart';
import 'package:argosy/features/search/search_providers.dart';
import 'package:argosy/features/search/tv/tv_search_screen.dart';
import 'package:argosy/tv/tv_focusable.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_home_fixtures.dart';

/// The box a focused [TvFocusable] paints into: the ring sits [focusOffset]
/// outside the content, the glow spreads past that, and the scale magnifies
/// both about the centre.
Rect _ring(Rect tile, {double scale = 1.06, double focusOffset = 5}) {
  final dx = tvFocusClearance(
    tile.width,
    scale: scale,
    focusOffset: focusOffset,
  );
  final dy = tvFocusClearance(
    tile.height,
    scale: scale,
    focusOffset: focusOffset,
  );
  return Rect.fromLTRB(
    tile.left - dx,
    tile.top - dy,
    tile.right + dx,
    tile.bottom + dy,
  );
}

/// Asserts the ring around the tile holding [label] survives the scroller it
/// lives in.
void _expectRingUnclipped(
  WidgetTester tester,
  String label, {
  double scale = 1.06,
  double focusOffset = 5,
}) {
  final tile = find
      .ancestor(of: find.text(label), matching: find.byType(TvFocusable))
      .first;
  final ring = _ring(
    tester.getRect(tile),
    scale: scale,
    focusOffset: focusOffset,
  );
  final viewport = tester.getRect(
    find.ancestor(of: tile, matching: find.byType(Scrollable)).first,
  );
  final reason =
      '$label: the scroller clips at $viewport, so the ring $ring '
      'would be sliced';
  expect(ring.left, greaterThanOrEqualTo(viewport.left), reason: reason);
  expect(ring.right, lessThanOrEqualTo(viewport.right), reason: reason);
  expect(ring.top, greaterThanOrEqualTo(viewport.top), reason: reason);
  expect(ring.bottom, lessThanOrEqualTo(viewport.bottom), reason: reason);
}

SeriesDetail _series() {
  EpisodeSummary ep(int n) => EpisodeSummary(
    id: 'ep-$n',
    episodeNumber: n,
    title: 'Episode $n',
    mediaItemId: 'item-$n',
    durationSeconds: 1400,
  );
  return SeriesDetail(
    id: 'series-1',
    title: 'Sword Art Online',
    seasons: [
      SeasonSummary(
        id: 's1',
        seasonNumber: 1,
        episodes: [for (var i = 1; i <= 6; i++) ep(i)],
      ),
    ],
  );
}

void main() {
  testWidgets('a home rail keeps the ring of its first and last tiles', (
    tester,
  ) async {
    await pumpTvHome(
      tester,
      homeData(continueRow: 4, onDeck: 1, recent: 4),
      scrollBy: 700,
    );

    // The first tile is the one flush against the rail's leading edge, and the
    // 16:9 continue tiles reach furthest sideways of anything on this screen.
    _expectRingUnclipped(tester, 'C1');
    _expectRingUnclipped(tester, 'D1');
    _expectRingUnclipped(tester, 'R1');
    // A tile mid-rail: the top of the ring is what the rail used to cut.
    _expectRingUnclipped(tester, 'R3');
  });

  testWidgets('an episode row keeps its ring inside the list', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seriesDetailProvider(
            'series-1',
          ).overrideWith((ref) async => _series()),
        ],
        child: const MaterialApp(home: TvSeriesScreen(seriesId: 'series-1')),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Rows run the full width of the list, so the sides are where the ring goes
    // first; the first row also sat flush against the top.
    _expectRingUnclipped(tester, 'Episode 1', scale: 1.02, focusOffset: 4);
    _expectRingUnclipped(tester, 'Episode 3', scale: 1.02, focusOffset: 4);
  });

  testWidgets('a search result keeps its ring inside the grid', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith(
            (ref) async => (
              films: [
                for (var i = 1; i <= 10; i++)
                  MediaCard(id: 'f$i', kind: MediaKind.movie, title: 'F$i'),
              ],
              series: <MediaCard>[],
            ),
          ),
        ],
        child: const MaterialApp(home: TvSearchScreen()),
      ),
    );
    await tester.pump();
    // The grid only renders past two characters, and the query is local state —
    // so type them the way the remote does.
    await tester.tap(find.text('A'));
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    // The leftmost column sat flush against the grid's viewport, and the top row
    // against its top edge.
    _expectRingUnclipped(tester, 'F1');
    _expectRingUnclipped(tester, 'F5');
  });

  testWidgets('the episode rows stay where the design puts them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seriesDetailProvider(
            'series-1',
          ).overrideWith((ref) async => _series()),
        ],
        child: const MaterialApp(home: TvSeriesScreen(seriesId: 'series-1')),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The clearance is reserved *inside* the list and given back by the margins
    // around it, so the row itself doesn't move: 56 + 540 (meta) + 64 from the
    // left, and 64 from the right edge of the 1920 stage.
    final row = tester.getRect(
      find
          .ancestor(
            of: find.text('Episode 1'),
            matching: find.byType(TvFocusable),
          )
          .first,
    );
    expect(row.left, 760);
    expect(row.right, 1920 - 64);
  });
}
