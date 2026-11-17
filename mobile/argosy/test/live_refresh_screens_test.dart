// What a silent refresh may and may not do to a screen that is already up
// (ARGY-291): a failed refetch keeps the page, and on TV a Resume/Play layout
// change waits until the remote leaves the action row.

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/tv/tv_movie_screen.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _itemId = 'item-1';

final _detail = MediaItemDetail(
  id: _itemId,
  kind: 'movie',
  title: 'Red October',
  filePath: 'films/hunt.mkv',
  reviewRequired: false,
);

final _midway = PlayState(
  positionSeconds: 600,
  durationSeconds: 6000,
  watched: false,
);
final _finished = PlayState(
  positionSeconds: 6000,
  durationSeconds: 6000,
  watched: true,
);

/// Server state the overridden provider reads on every (re)fetch.
class _Server {
  PlayState? progress = _midway;
  bool fail = false;
}

Future<ProviderContainer> _pumpTvMovie(WidgetTester tester, _Server server) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryApiProvider.overrideWithValue(LibraryApi(ApiClient())),
        movieDetailProvider(_itemId).overrideWith((ref) async {
          if (server.fail) throw const ApiFailure('offline');
          return (detail: _detail, progress: server.progress);
        }),
      ],
      child: const MaterialApp(home: TvMovieScreen(itemId: _itemId)),
    ),
  );
  await tester.pump();
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(TvMovieScreen)));
}

Future<void> _refetch(WidgetTester tester, ProviderContainer c) async {
  c.invalidate(movieDetailProvider(_itemId));
  await tester.pump();
  await tester.pump();
}

bool _focused(WidgetTester tester, Finder f) =>
    Focus.of(tester.element(f)).hasFocus;

void main() {
  testWidgets('a refetch that fails keeps the page instead of an error', (
    tester,
  ) async {
    final server = _Server();
    final c = await _pumpTvMovie(tester, server);
    expect(find.text('Red October'), findsOneWidget);

    server.fail = true; // e.g. the app resumed with no network
    await _refetch(tester, c);

    expect(find.text('Red October'), findsOneWidget);
    expect(find.text('offline'), findsNothing);
  });

  testWidgets('a first load that fails still shows the error', (tester) async {
    await _pumpTvMovie(tester, _Server()..fail = true);
    expect(find.text('offline'), findsOneWidget);
  });

  testWidgets('TV: the action row keeps its layout while focused in it', (
    tester,
  ) async {
    final server = _Server();
    final c = await _pumpTvMovie(tester, server);
    final resume = find.textContaining('Resume');
    expect(resume, findsOneWidget);
    expect(_focused(tester, resume), isTrue); // the landing focus

    server.progress = _finished; // another device finished the film
    await _refetch(tester, c);

    // The row still reads Resume / Play from start, focus has not moved, and
    // the watched label is already current.
    expect(resume, findsOneWidget);
    expect(_focused(tester, resume), isTrue);
    expect(find.text('Watched'), findsOneWidget);

    // Leaving the row (LEFT to the nav rail) lets the new layout land.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Resume'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('TV: with focus elsewhere the new layout applies at once', (
    tester,
  ) async {
    final server = _Server();
    final c = await _pumpTvMovie(tester, server);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft); // to the rail
    await tester.pump();
    expect(_focused(tester, find.textContaining('Resume')), isFalse);

    server.progress = _finished;
    await _refetch(tester, c);

    expect(find.textContaining('Resume'), findsNothing);
    expect(find.text('Play'), findsOneWidget);
  });
}
