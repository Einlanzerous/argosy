import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy/features/player/player_controls.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wiring that was actually broken in ARGY-280: the phone overlay must
/// derive "may hide" from the *controller's* state — playing, past `starting`,
/// no fatal error — on every update, not from a single timer armed at mount.
/// These pump the real [PlayerControls] over a controller whose player value
/// is driven by hand (there is no better_player under test), and read the
/// overlay's fade through its [AnimatedOpacity]. Drop `_syncCanHide` from both
/// its call sites and the first test fails: the controls never fade.
class _DrivenPlayback extends PlaybackController {
  _DrivenPlayback()
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
        );

  VideoPlayerValue? _value;
  final seeks = <double>[];

  @override
  VideoPlayerValue? get videoValue => _value;

  /// No player or server under test: a real seek would fail the session and
  /// swap the overlay for the error view. Record it instead.
  @override
  Future<void> seekTo(double target) async => seeks.add(target);

  /// What the controller's `play`/`pause` event handlers amount to for the
  /// overlay: a new player value and a notify.
  void drive({required bool playing, bool starting = false}) {
    _value = VideoPlayerValue(
      duration: const Duration(minutes: 22),
      isPlaying: playing,
    );
    this.starting = starting;
    notifyListeners();
  }
}

const _hideAfter = Duration(milliseconds: 3500);

Future<_DrivenPlayback> _pump(WidgetTester tester) async {
  final c = _DrivenPlayback();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlayerControls(controller: c, title: 'Pilot', onBack: () {}),
      ),
    ),
  );
  return c;
}

double _opacity(WidgetTester tester) {
  final fade = find.descendant(
    of: find.byType(PlayerControls),
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(fade).opacity;
}

/// A point on the bare video: below the top bar, left of the centre buttons.
Offset _bareVideo(WidgetTester tester) =>
    tester.getTopLeft(find.byType(PlayerControls)) + const Offset(40, 200);

void main() {
  testWidgets('controls stay up while starting and fade 3.5s after first play',
      (tester) async {
    final c = await _pump(tester);
    c.drive(playing: false, starting: true);
    await tester.pump();
    expect(_opacity(tester), 1);

    // The transcode's spin-up: longer than the fade. The old one-shot timer
    // expired in here and nothing re-armed it.
    await tester.pump(const Duration(seconds: 10));
    expect(_opacity(tester), 1, reason: 'nothing to hide while starting');

    c.drive(playing: true); // the `play` event
    await tester.pump();
    await tester.pump(_hideAfter - const Duration(milliseconds: 100));
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 0, reason: 'first play must start the countdown');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pause from the controller holds them; resume fades them again',
      (tester) async {
    final c = await _pump(tester);
    c.drive(playing: true);
    await tester.pump(const Duration(seconds: 1));

    // Paused from anywhere (notification, PiP action, headset) — only the
    // controller update arrives, no on-screen interaction.
    c.drive(playing: false);
    await tester.pump(const Duration(seconds: 30));
    expect(_opacity(tester), 1, reason: 'paused controls never fade');

    c.drive(playing: true);
    await tester.pump(_hideAfter + const Duration(milliseconds: 100));
    expect(_opacity(tester), 0, reason: 'resume alone restarts the countdown');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a tap on the video brings them back and they fade again',
      (tester) async {
    final c = await _pump(tester);
    c.drive(playing: true);
    await tester.pump(_hideAfter + const Duration(milliseconds: 100));
    expect(_opacity(tester), 0);

    await tester.tapAt(_bareVideo(tester));
    await tester.pump();
    expect(_opacity(tester), 1);

    await tester.pump(_hideAfter - const Duration(milliseconds: 100));
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a seek re-arms the countdown', (tester) async {
    final c = await _pump(tester);
    c.drive(playing: true);
    await tester.pump(const Duration(seconds: 3)); // 0.5s from fading

    await tester.tap(find.byIcon(Icons.forward_10));
    expect(c.seeks, [10.0]);
    await tester.pump(const Duration(seconds: 3));
    expect(_opacity(tester), 1, reason: 'the seek restarted the 3.5s');
    await tester.pump(const Duration(milliseconds: 600));
    expect(_opacity(tester), 0);

    await tester.pumpWidget(const SizedBox());
  });
}
