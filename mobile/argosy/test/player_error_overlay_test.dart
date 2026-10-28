import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy/features/player/player_controls.dart';
import 'package:argosy/features/player/player_modal_shell.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARGY-284: the fatal-error view used to be a bare icon + text + outlined
/// button floating on the video, unreadable over a bright frame. It now sits on
/// the resume prompt's scrim with a filled Retry.
class _FailedPlayback extends PlaybackController {
  _FailedPlayback()
      : super(
          libraryApi: LibraryApi(ApiClient()),
          transcodeApi: TranscodeApi(ApiClient()),
          authApi: AuthApi(ApiClient()),
          baseUrl: 'http://localhost',
          token: null,
          itemId: 'item-1',
          title: 'The Series Has Landed',
          catalogDuration: 1320,
          isTranscode: true,
          hevc: false,
          hevcHardware: false,
          subtitles: const [],
          preferredLanguages: const [],
          prefs: null,
        ) {
    fatalError = true;
    errorMessage = 'The connection dropped.';
  }

  int retries = 0;

  @override
  Future<void> retry() async => retries++;
}

class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

void main() {
  testWidgets('error overlay: scrim, message, filled Retry, back arrow',
      (tester) async {
    final c = _FailedPlayback();
    addTearDown(c.dispose);
    final observer = _PopObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Colors.white), // bright frame
                          PlayerControls(
                            controller: c,
                            title: 'Pilot',
                            onBack: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                child: const Text('open player'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open player'));
    await tester.pumpAndSettle();

    final scrim = find.descendant(
      of: find.byType(PlayerModalShell),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xE6000000),
      ),
    );
    expect(scrim, findsOneWidget);
    expect(find.text('PLAYBACK ERROR'), findsOneWidget);
    expect(find.text('The connection dropped.'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Filled, not outlined: FilledButton.icon builds a FilledButton subclass.
    final retry = find.widgetWithText(FilledButton, 'Retry');
    expect(retry, findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(retry);
    expect(c.retries, 1);

    // The back arrow must always leave, whatever the controller is doing.
    expect(observer.pops, 0);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(observer.pops, 1);
    expect(find.byType(PlayerControls), findsNothing);
    expect(find.text('open player'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
