// Shared TV Home fixtures for the focus tests (ARGY-184).
//
// The rails are what's under test, so the tiles carry deliberately short,
// distinct titles — C1.. on Continue Watching, D1.. on On Deck, R1.. on Newly
// Arrived — and every test pumps at the real 1920×1080 TvStage size so the rects
// it reads are the ones the panel lays out.

import 'package:argosy/features/browse/media_card.dart';
import 'package:argosy/features/home/home_providers.dart';
import 'package:argosy/features/home/tv/tv_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const tvHomeHero = HomeHero(
  eyebrow: 'Continue watching',
  title: 'Sword Art Online',
  kind: MediaKind.series,
  detailId: 'series-1',
  playableId: 'episode-1',
  percent: 0.4,
);

HomeData homeData({int continueRow = 0, int onDeck = 0, int recent = 0}) {
  return HomeData(
    hero: tvHomeHero,
    continueRow: [
      for (var i = 1; i <= continueRow; i++)
        ContinueEntry(
          id: 'c$i',
          kind: MediaKind.movie,
          title: 'C$i',
          progress: 0.5,
          remainingLabel: '12m left',
        ),
    ],
    onDeck: [for (var i = 1; i <= onDeck; i++) _card('D$i')],
    recent: [for (var i = 1; i <= recent; i++) _card('R$i')],
  );
}

MediaCard _card(String id) =>
    MediaCard(id: id, kind: MediaKind.movie, title: id, year: 2020);

/// Pumps TV Home at TV size, optionally scrolling [scrollBy] down first — the
/// page builds lazily, and the rails below Continue Watching only exist once
/// they're near the viewport.
Future<void> pumpTvHome(
  WidgetTester tester,
  HomeData data, {
  double scrollBy = 0,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [homeDataProvider.overrideWith((ref) async => data)],
      child: const MaterialApp(home: TvHomeScreen()),
    ),
  );
  // Resolve the future and mount the page, then run the post-frame focus claim.
  await tester.pump();
  await tester.pump();

  if (scrollBy != 0) {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -scrollBy));
    await tester.pumpAndSettle();
  }
}

/// Whether the tile titled [label] holds focus.
bool tvTileFocused(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label))).hasFocus;
