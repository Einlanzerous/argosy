// The season-wide Stow button (ARGY-229): it reads the season's aggregate
// state off the same controller the episode rows use, and puts the matching
// bulk action behind a confirmation.

import 'dart:async';
import 'dart:io';

import 'package:argosy/api/api_providers.dart';
import 'package:argosy/features/stow/stow_button.dart';
import 'package:argosy/features/stow/stow_controller.dart';
import 'package:argosy/features/stow/stow_service.dart';
import 'package:argosy/features/stow/stow_store.dart';
import 'package:argosy/features/stow/stowed_item.dart';
import 'package:argosy/theme/argosy_theme.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Never answers a detail fetch, so a season stow sits at "Preparing…" for
/// as long as the test needs to look at it — and never reaches the network.
class _StalledLibraryApi extends LibraryApi {
  @override
  Future<MediaItemDetail?> getMediaItem(
    String itemId, {
    Future<void>? abortTrigger,
  }) => Completer<MediaItemDetail?>().future;
}

const _ids = ['ep-1', 'ep-2', 'ep-3'];

void main() {
  late Directory root;
  late StowStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('argosy-season-stow');
    store = StowStore(root: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Puts [ids] on the device as finished stows, file and index row both, so
  /// a reconcile against disk keeps them.
  Future<void> seed(WidgetTester tester, List<String> ids) async {
    await tester.runAsync(() async {
      for (final id in ids) {
        final dir = await store.itemDir(id);
        await File('${dir.path}/video.mp4').writeAsBytes(const [1]);
        await store.put(
          StowedItem(
            itemId: id,
            title: id,
            fileName: 'video.mp4',
            bytes: 1,
            stowedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stowStoreProvider.overrideWithValue(store),
          stowEngineProvider.overrideWithValue(
            LocalStowEngine(store: store, connect: () async => throw 'unused'),
          ),
          libraryApiProvider.overrideWithValue(_StalledLibraryApi()),
        ],
        child: MaterialApp(
          theme: buildArgosyTheme(),
          home: Scaffold(
            body: SeasonStowButton(
              seasonLabel: 'Season 1',
              entries: [
                for (final id in _ids) (itemId: id, subtitleLine: 'S1 · $id'),
              ],
            ),
          ),
        ),
      ),
    );
    // Let the stowed-items provider resolve so the button reads the index.
    await tester.pump();
  }

  testWidgets('offers to stow a season with nothing on the device', (
    tester,
  ) async {
    await pumpButton(tester);
    expect(find.text('Stow season'), findsOneWidget);
  });

  testWidgets('a partly stowed season still offers to stow the rest', (
    tester,
  ) async {
    await seed(tester, ['ep-1']);
    await pumpButton(tester);
    expect(find.text('Stow season'), findsOneWidget);
  });

  testWidgets('counts the season down while episodes are in flight', (
    tester,
  ) async {
    await seed(tester, ['ep-1']);
    await pumpButton(tester);

    await tester.tap(find.text('Stow season'));
    await tester.pump();

    expect(
      find.text('Stowing season · 1 of 3'),
      findsOneWidget,
      reason: 'the stowed one counts; the two just queued do not',
    );

    // Tapping mid-flight asks before cancelling anything.
    await tester.tap(find.text('Stowing season · 1 of 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel season download?'), findsOneWidget);
    expect(find.textContaining('2 episodes of Season 1'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stowing season · 1 of 3'), findsOneWidget);
  });

  testWidgets(
    'a season fully on the device reads as stowed and offers removal',
    (tester) async {
      await seed(tester, _ids);
      await pumpButton(tester);
      expect(find.text('Season stowed'), findsOneWidget);

      await tester.tap(find.text('Season stowed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Remove Season 1 from this device?'), findsOneWidget);
      expect(find.textContaining('3 episodes will be deleted'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    },
  );
}
