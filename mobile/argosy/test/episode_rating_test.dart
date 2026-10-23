// Per-episode rating badge on the phone and TV series detail rows (ARGY-256).

import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/series_detail_screen.dart';
import 'package:argosy/features/detail/tv/tv_series_screen.dart';
import 'package:argosy/theme/argosy_theme.dart';
import 'package:argosy/util/format.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SeriesDetail _series() {
  EpisodeSummary ep(int n, {double? rating}) => EpisodeSummary(
    id: 'ep-$n',
    episodeNumber: n,
    title: 'Episode $n',
    mediaItemId: 'item-$n',
    durationSeconds: 1400,
    rating: rating,
  );
  return SeriesDetail(
    id: 'series-1',
    title: 'Sword Art Online',
    seasons: [
      SeasonSummary(
        id: 's1',
        seasonNumber: 1,
        episodes: [ep(1, rating: 8.14), ep(2)],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seriesDetailProvider('series-1').overrideWith((ref) async => _series()),
      ],
      child: MaterialApp(theme: buildArgosyTheme(), home: screen),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('episodeRatingLabel', () {
    test('one decimal with a star', () {
      expect(episodeRatingLabel([8.14]), '★ 8.1');
      expect(episodeRatingLabel([7]), '★ 7.0');
    });
    test('null when nothing is rated', () {
      expect(episodeRatingLabel([]), isNull);
      expect(episodeRatingLabel([null, null]), isNull);
    });
    test('a combined row takes the first rated episode', () {
      expect(episodeRatingLabel([null, 6.5, 9.0]), '★ 6.5');
    });
  });

  testWidgets('phone rows show the rating only when present', (tester) async {
    await _pump(tester, const SeriesDetailScreen(seriesId: 'series-1'));
    expect(find.text('★ 8.1'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-rating')), findsOneWidget);
  });

  testWidgets('TV rows show the rating only when present', (tester) async {
    await _pump(tester, const TvSeriesScreen(seriesId: 'series-1'));
    expect(find.text('★ 8.1'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-rating')), findsOneWidget);
  });
}
