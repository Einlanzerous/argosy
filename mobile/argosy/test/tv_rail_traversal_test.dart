// D-pad Up/Down between the TV Home rails (ARGY-184).
//
// Flutter's directional traversal takes the nearest node that overlaps the
// focused node's horizontal band and only looks out-of-band when nothing is in
// it. Rails put their tiles wherever their own scroll offset does, so a rail
// with few items often shares no band with the tile you're on — and Up sails
// over it into the rail above. TvRailGroup makes the hop explicit instead.
//
// Focus behaviour is exactly what a dongle would show, and the dongle isn't
// reliably reachable from the dev box, so it's pinned here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tv_home_fixtures.dart';

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The horizontal centre of a tile — invariant under the focus scale, which
/// grows about it.
double _centerX(WidgetTester tester, String label) => tester
    .getRect(
      find.ancestor(of: find.text(label), matching: find.byType(Focus)).first,
    )
    .center
    .dx;

Future<void> _focus(WidgetTester tester, String label) async {
  Focus.of(tester.element(find.text(label))).requestFocus();
  await tester.pumpAndSettle();
  expect(tvTileFocused(tester, label), isTrue);
}

void main() {
  testWidgets('Up lands in the rail above, however few items it holds', (
    tester,
  ) async {
    // The reported shape: one item On Deck, between a long Continue Watching
    // and a long Newly Arrived.
    await pumpTvHome(
      tester,
      homeData(continueRow: 3, onDeck: 1, recent: 8),
      scrollBy: 700,
    );
    await _focus(tester, 'R4');

    await _press(tester, LogicalKeyboardKey.arrowUp);

    expect(
      tvTileFocused(tester, 'D1'),
      isTrue,
      reason: 'On Deck is the rail directly above Newly Arrived',
    );
    expect(
      tvTileFocused(tester, 'C2'),
      isFalse,
      reason:
          "R4 shares no horizontal band with On Deck's only tile, so plain "
          'directional traversal jumped the rail entirely and landed here',
    );
  });

  testWidgets('Down comes back into the rail below', (tester) async {
    await pumpTvHome(
      tester,
      homeData(continueRow: 3, onDeck: 1, recent: 8),
      scrollBy: 700,
    );
    await _focus(tester, 'D1');

    await _press(tester, LogicalKeyboardKey.arrowDown);

    expect(tvTileFocused(tester, 'R1'), isTrue);
  });

  testWidgets('the hop lands on the tile nearest the column you came from', (
    tester,
  ) async {
    // A short rail with a real choice in it: On Deck's three tiles all sit left
    // of the tile being left, so none of them is in its band. The nearest is the
    // last one — not the first, which is what falling back to the start of the
    // rail would give.
    await pumpTvHome(
      tester,
      homeData(continueRow: 6, onDeck: 3, recent: 8),
      scrollBy: 700,
    );
    await _focus(tester, 'R7');

    // Where everything sits at the moment of the press. Focusing a tile scrolls
    // its rail, so these have to be read now, not after the hop.
    final onDeck = ['D1', 'D2', 'D3'];
    final columns = {for (final tile in onDeck) tile: _centerX(tester, tile)};
    final from = _centerX(tester, 'R7');

    await _press(tester, LogicalKeyboardKey.arrowUp);

    final landed = onDeck.firstWhere(
      (tile) => tvTileFocused(tester, tile),
      orElse: () => 'nothing — the hop missed the On Deck rail',
    );
    final nearest = onDeck.reduce(
      (a, b) =>
          (columns[a]! - from).abs() <= (columns[b]! - from).abs() ? a : b,
    );
    expect(
      landed,
      nearest,
      reason:
          'the remote was pointing at $from; $nearest is the On Deck tile under '
          'it, and index-matching would have drifted — the rails have different '
          'tile widths and gaps',
    );
  });

  testWidgets('Up out of the first rail still reaches the hero', (
    tester,
  ) async {
    // The group only owns hops *between* rails. Above the top one is the hero,
    // and below the last is nothing — both are ordinary traversal's to answer,
    // and swallowing the key would strand the remote in the rails.
    await pumpTvHome(tester, homeData(continueRow: 3, onDeck: 1, recent: 8));
    await _focus(tester, 'C1');

    await _press(tester, LogicalKeyboardKey.arrowUp);

    expect(Focus.of(tester.element(find.text('Resume'))).hasFocus, isTrue);
  });

  testWidgets('Down out of the last rail stays put', (tester) async {
    await pumpTvHome(
      tester,
      homeData(continueRow: 3, onDeck: 1, recent: 8),
      scrollBy: 700,
    );
    await _focus(tester, 'R2');

    await _press(tester, LogicalKeyboardKey.arrowDown);

    expect(tvTileFocused(tester, 'R2'), isTrue);
  });
}
