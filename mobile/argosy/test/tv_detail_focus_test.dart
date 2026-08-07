// Landing focus on the TV detail screens (ARGY-173).
//
// The guard itself is covered in tv_landing_focus_test; this checks the wiring
// on a real screen — that the primary action is the node handed to
// TvLandingFocus.claimOnMount, and that the screen actually has the wrapper
// (without it the claim asserts).

import 'package:argosy/features/detail/detail_providers.dart';
import 'package:argosy/features/detail/tv/tv_movie_screen.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _itemId = 'item-1';

MediaItemDetail _film() => MediaItemDetail(
  id: _itemId,
  kind: 'movie',
  title: 'The Hunt for Red October',
  filePath: 'films/hunt.mkv',
  reviewRequired: false,
);

Future<void> _pumpMovie(WidgetTester tester, {PlayState? progress}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        movieDetailProvider(
          _itemId,
        ).overrideWith((ref) async => (detail: _film(), progress: progress)),
      ],
      child: const MaterialApp(home: TvMovieScreen(itemId: _itemId)),
    ),
  );
  // Resolve the future, mount the actions, then run the post-frame claim.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a film with no progress lands on Play', (tester) async {
    await _pumpMovie(tester);

    expect(find.text('Play'), findsOneWidget);
    expect(
      Focus.of(tester.element(find.text('Play'))).hasFocus,
      isTrue,
      reason: 'the first SELECT should start the film, not re-select the rail',
    );
  });

  testWidgets('a partly-watched film lands on Resume', (tester) async {
    await _pumpMovie(
      tester,
      progress: PlayState(
        positionSeconds: 600,
        durationSeconds: 6000,
        watched: false,
      ),
    );

    final resume = find.textContaining('Resume');
    expect(resume, findsOneWidget);
    expect(Focus.of(tester.element(resume)).hasFocus, isTrue);
    // Play from start renders alongside it and must not be what holds focus.
    expect(
      Focus.of(tester.element(find.text('Play from start'))).hasFocus,
      isFalse,
    );
  });
}
