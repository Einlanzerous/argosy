// A detail screen stays mounted beneath the full-screen player route, so its
// autoDispose provider was never refetched when the player popped and episodes
// you had just watched kept showing as unwatched (ARGY-266). This drives the
// real screen under a real GoRouter, pushes the player by tapping an episode and
// pops it, and checks the three things the fix promises: the provider refetches,
// the old content stays up while it does (no spinner), and the optimistic
// overrides yield to the server's answer.

import 'dart:async';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/series_detail_screen.dart';
import 'package:argosy/theme/argosy_theme.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  /// What each successive getSeries call reports for the episode; the last
  /// entry repeats. Calls after the first wait on [gate] when it is set, so the
  /// test can look at the screen while the refetch is in flight.
  final List<bool> serverWatched = [];
  Completer<void>? gate;

  /// Per-fetch gates, keyed by 1-based fetch number, to order the answers.
  final Map<int, Completer<void>> gates = {};
  int fetches = 0;

  @override
  Future<SeriesDetail?> getSeries(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final i = fetches < serverWatched.length
        ? fetches
        : serverWatched.length - 1;
    fetches++;
    final n = fetches;
    if (fetches > 1 && gate != null) await gate!.future;
    if (gates[n] case final g?) await g.future;
    return _series(watched: serverWatched[i]);
  }

  @override
  Future<WatchedBulkResult?> setSeasonWatched(
    String seasonId,
    WatchedUpdate watchedUpdate, {
    Future<void>? abortTrigger,
  }) async => null;
}

SeriesDetail _series({required bool watched}) => SeriesDetail(
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
          watched: watched,
        ),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, _Library api) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SeriesDetailScreen(seriesId: 'series-1'),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.pop(),
            child: const Text('close player'),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [libraryApiProvider.overrideWithValue(api)],
      child: MaterialApp.router(
        theme: buildArgosyTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _playAndClose(WidgetTester tester) async {
  await tester.tap(find.text('Pilot'));
  await tester.pumpAndSettle();
  expect(find.text('close player'), findsOneWidget);
  await tester.tap(find.text('close player'));
  await tester.pump(); // route pops, openPlayer's future completes
  await tester.pump(const Duration(milliseconds: 400)); // transition
}

void main() {
  testWidgets('refetches on return from the player without a spinner', (
    tester,
  ) async {
    final api = _Library()..serverWatched.addAll([false, true]);
    await _pump(tester, api);
    expect(api.fetches, 1);
    expect(find.text('Not started'), findsOneWidget);

    api.gate = Completer<void>();
    await _playAndClose(tester);

    // Refetch is in flight: the stale list is still on screen, no spinner.
    expect(api.fetches, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Pilot'), findsOneWidget);

    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Not started'), findsNothing);
    expect(find.textContaining('Watched'), findsWidgets);
  });

  testWidgets('optimistic overrides yield to the refetched server state', (
    tester,
  ) async {
    // The write lands (fetch 2, which the toggle triggers, reports it), then
    // another device unmarks the episode before the player returns (fetch 3).
    final api = _Library()..serverWatched.addAll([false, true, false]);
    await _pump(tester, api);

    await tester.tap(find.text('Mark season watched'));
    await tester.pumpAndSettle();
    expect(find.text('Not started'), findsNothing); // override applied
    expect(api.fetches, 2); // ...and confirmed by a refetch (ARGY-291)

    await _playAndClose(tester);
    await tester.pumpAndSettle();

    expect(api.fetches, 3);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('a refetch already in flight cannot undo a watched tap', (
    tester,
  ) async {
    // Fetch 2 started before the write and answers with the old state; the
    // toggle's own refetch (fetch 3) answers with the new one (ARGY-291).
    final api = _Library()..serverWatched.addAll([false, false, true]);
    await _pump(tester, api);

    final stale = api.gates[2] = Completer<void>();
    final fresh = api.gates[3] = Completer<void>();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SeriesDetailScreen)),
    );
    container.invalidate(seriesDetailProvider('series-1')); // e.g. app resume
    await tester.pump();
    expect(api.fetches, 2);

    await tester.tap(find.text('Mark season watched'));
    await tester.pump();
    expect(api.fetches, 3);

    // The newer answer arrives first and the stale one last: only the newer
    // may count.
    fresh.complete();
    await tester.pumpAndSettle();
    stale.complete();
    await tester.pumpAndSettle();
    expect(find.text('Not started'), findsNothing);
  });
}
