// Where the remote lands when TV Home opens (ARGY-173).
//
// The nav rail deliberately autofocuses on the first frame — it exists before
// the async home data does, which is what stops the route's modal scope
// self-focusing and killing D-pad traversal. The cost was that focus stayed
// there: Home is a no-op destination, so the first SELECT did nothing and
// reaching Resume took two presses. The hero now claims focus once it mounts.
//
// Worth testing here rather than only on a device: this is pure focus
// behaviour, and a Google TV dongle isn't always reachable.

import 'package:argosy/features/browse/media_card.dart';
import 'package:argosy/features/home/home_providers.dart';
import 'package:argosy/features/home/tv/tv_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps TV Home with a fixed hero, then lets the post-frame focus request run.
Future<void> _pumpHome(WidgetTester tester, HomeData data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [homeDataProvider.overrideWith((ref) async => data)],
      child: const MaterialApp(home: TvHomeScreen()),
    ),
  );
  // First pump resolves the future and mounts the hero; the second runs the
  // post-frame callback that requests focus.
  await tester.pump();
  await tester.pump();
}

const _playableHero = HomeHero(
  eyebrow: 'Continue watching',
  title: 'Sword Art Online',
  kind: MediaKind.series,
  detailId: 'series-1',
  playableId: 'episode-1',
  percent: 0.4,
);

void main() {
  testWidgets('focus lands on the hero Resume action, not the nav rail', (
    tester,
  ) async {
    await _pumpHome(tester, const HomeData(hero: _playableHero));

    expect(find.text('Resume'), findsOneWidget);
    expect(
      Focus.of(tester.element(find.text('Resume'))).hasFocus,
      isTrue,
      reason: 'the first SELECT press should resume the hero',
    );
    // The secondary action must not be the one holding focus — reaching Resume
    // via directional traversal from there is the behaviour being fixed.
    expect(Focus.of(tester.element(find.text('Episodes'))).hasFocus, isFalse);
  });

  testWidgets('falls back to the secondary action when nothing is playable', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      const HomeData(
        hero: HomeHero(
          eyebrow: 'Featured',
          title: 'Shogun',
          kind: MediaKind.series,
          detailId: 'series-2',
        ),
      ),
    );

    expect(find.text('Resume'), findsNothing);
    expect(find.text('Play'), findsNothing);
    expect(
      Focus.of(tester.element(find.text('Episodes'))).hasFocus,
      isTrue,
      reason: 'with no playable id, Episodes is the first action',
    );
  });

  testWidgets('a refresh does not pull focus back to the hero', (tester) async {
    final container = ProviderContainer(
      overrides: [
        homeDataProvider.overrideWith((ref) async => const HomeData(hero: _playableHero)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TvHomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Resume'))).hasFocus, isTrue);

    // Move focus the way a viewer would, then let a Beacon-style refresh land.
    Focus.of(tester.element(find.text('Episodes'))).requestFocus();
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Episodes'))).hasFocus, isTrue);

    container.refresh(homeDataProvider);
    await tester.pump();
    await tester.pump();

    expect(
      Focus.of(tester.element(find.text('Episodes'))).hasFocus,
      isTrue,
      reason: 'a data refresh rebuilds the hero but must not re-run initState '
          'and steal focus from wherever the viewer has moved it',
    );
  });
}
