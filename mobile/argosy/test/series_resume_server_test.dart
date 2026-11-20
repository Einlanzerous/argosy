// The series screen's Resume button takes the server's answer (ARGY-320), the
// same recency rule that drives home's Continue Watching. Reproduces Arin's
// Scrubs: S3E18 in progress (newest), with a stray at 8s in a bulk-unwatched
// season 8. The old client-side rule picked the furthest-along stray, S8E9.

import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/tv/tv_series_screen.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeSummary _ep(int n, {double position = 0, bool watched = false}) =>
    EpisodeSummary(
      id: 'e$n',
      episodeNumber: n,
      mediaItemId: 'm$n',
      positionSeconds: position,
      durationSeconds: 1200,
      watched: watched,
    );

SeriesDetail _scrubs({String? resumeItemId}) => SeriesDetail(
  id: 'series-1',
  title: 'Scrubs',
  resumeItemId: resumeItemId,
  seasons: [
    SeasonSummary(
      id: 's3',
      seasonNumber: 3,
      episodes: [_ep(17, watched: true), _ep(18, position: 136), _ep(19)],
    ),
    SeasonSummary(
      id: 's8',
      seasonNumber: 8,
      episodes: [
        for (var i = 1; i <= 9; i++) _ep(80 + i, position: i == 9 ? 8 : 0),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, SeriesDetail series) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seriesDetailProvider('series-1').overrideWith((ref) async => series),
      ],
      child: const MaterialApp(home: TvSeriesScreen(seriesId: 'series-1')),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('resumes where the server says, not at a sub-threshold stray', (
    tester,
  ) async {
    await _pump(tester, _scrubs(resumeItemId: 'm18'));
    expect(find.text('Resume · S3 E18'), findsOneWidget);
    expect(find.textContaining('Resume · S8'), findsNothing);
  });

  testWidgets('no server resume target means a plain Play', (tester) async {
    await _pump(tester, _scrubs());
    expect(find.textContaining('Resume'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });
}
