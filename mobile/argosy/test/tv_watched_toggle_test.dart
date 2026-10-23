// D-pad watched toggle on the TV detail screens (ARGY-257).
//
// The toggle must flip watched state through the same LibraryApi calls the
// phone uses, and must do it without moving focus: a rebuild that dropped the
// button the viewer just pressed would strand the D-pad on the nav rail.

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/tv/tv_movie_screen.dart';
import 'package:argosy/features/detail/tv/tv_series_screen.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibraryApi extends LibraryApi {
  _FakeLibraryApi({this.fail = false});

  final bool fail;
  final List<({String id, bool watched})> calls = [];

  @override
  Future<PlayState?> setWatched(
    String itemId,
    WatchedUpdate watchedUpdate, {
    Future<void>? abortTrigger,
  }) async {
    if (fail) throw Exception('boom');
    calls.add((id: itemId, watched: watchedUpdate.watched));
    return null;
  }
}

const _itemId = 'item-1';

Future<void> _pumpMovie(WidgetTester tester, _FakeLibraryApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        movieDetailProvider(_itemId).overrideWith(
          (ref) async => (
            detail: MediaItemDetail(
              id: _itemId,
              kind: 'movie',
              title: 'Red October',
              filePath: 'films/hunt.mkv',
              reviewRequired: false,
            ),
            progress: null,
          ),
        ),
      ],
      child: const MaterialApp(home: TvMovieScreen(itemId: _itemId)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

SeriesDetail _series() => SeriesDetail(
  id: 'series-1',
  title: 'Show',
  seasons: [
    SeasonSummary(
      id: 'season-1',
      seasonNumber: 1,
      episodes: [
        EpisodeSummary(
          id: 'e1',
          episodeNumber: 1,
          title: 'Pilot',
          mediaItemId: 'm1',
          watched: false,
        ),
        EpisodeSummary(
          id: 'e2',
          episodeNumber: 2,
          title: 'Second',
          mediaItemId: 'm2',
          watched: true,
        ),
      ],
    ),
  ],
);

Future<void> _pumpSeries(WidgetTester tester, _FakeLibraryApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(api),
        seriesDetailProvider('series-1').overrideWith((ref) async => _series()),
      ],
      child: const MaterialApp(home: TvSeriesScreen(seriesId: 'series-1')),
    ),
  );
  await tester.pump();
  await tester.pump();
}

bool _hasFocus(WidgetTester tester, Finder f) =>
    Focus.of(tester.element(f)).hasFocus;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('movie: Mark watched toggles and keeps focus on the button', (
    tester,
  ) async {
    final api = _FakeLibraryApi();
    await _pumpMovie(tester, api);

    final button = find.text('Mark watched');
    expect(button, findsOneWidget);
    // Land on Play, then RIGHT twice: Add to Vault, then the toggle.
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_hasFocus(tester, button), isTrue);

    await _key(tester, LogicalKeyboardKey.select);

    expect(api.calls, [(id: _itemId, watched: true)]);
    expect(find.text('Watched'), findsOneWidget);
    expect(find.text('Mark watched'), findsNothing);
    expect(_hasFocus(tester, find.text('Watched')), isTrue);

    await _key(tester, LogicalKeyboardKey.select);
    expect(api.calls.last, (id: _itemId, watched: false));
    expect(find.text('Mark watched'), findsOneWidget);
    expect(_hasFocus(tester, find.text('Mark watched')), isTrue);
  });

  testWidgets('movie: a failed save leaves the label and focus alone', (
    tester,
  ) async {
    await _pumpMovie(tester, _FakeLibraryApi(fail: true));

    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    await _key(tester, LogicalKeyboardKey.select);

    expect(find.text('Mark watched'), findsOneWidget);
    expect(find.text("Couldn't update watched state"), findsOneWidget);
    expect(_hasFocus(tester, find.text('Mark watched')), isTrue);
  });

  testWidgets('series: the episode toggle flips state and keeps focus', (
    tester,
  ) async {
    final api = _FakeLibraryApi();
    await _pumpSeries(tester, api);

    // Episode 1 is unwatched, episode 2 watched.
    final unwatched = find.byIcon(Icons.check_circle_outline);
    expect(unwatched, findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    Focus.of(tester.element(unwatched)).requestFocus();
    await tester.pump();
    expect(_hasFocus(tester, unwatched), isTrue);

    await _key(tester, LogicalKeyboardKey.select);

    expect(api.calls, [(id: 'm1', watched: true)]);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    // Still the same toggle: the rebuild did not strand focus.
    final first = find.byIcon(Icons.check_circle).first;
    expect(_hasFocus(tester, first), isTrue);
  });

  testWidgets('series: LEFT from a toggle returns to its own episode row', (
    tester,
  ) async {
    await _pumpSeries(tester, _FakeLibraryApi());

    final toggle = find.byIcon(Icons.check_circle_outline);
    Focus.of(tester.element(find.text('Pilot'))).requestFocus();
    await tester.pump();

    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_hasFocus(tester, toggle), isTrue, reason: 'RIGHT enters the toggle');

    await _key(tester, LogicalKeyboardKey.arrowLeft);

    expect(_hasFocus(tester, toggle), isFalse);
    expect(
      _hasFocus(tester, find.text('Pilot')),
      isTrue,
      reason: 'LEFT lands on the row, not the primary action',
    );
  });
}
