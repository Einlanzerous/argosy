import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dismissing the Android PiP window destroys the host activity without tearing
/// down the widget tree, so [PlaybackController.dispose] never runs and the
/// server keeps transcoding (ARGY-190). The controller watches the app lifecycle
/// to catch that, and `detached` is the *only* state that means it: PiP itself
/// reports `inactive`/`paused`, and treating either as a teardown would kill the
/// session of a video the viewer is still watching in the floating window.
PlaybackController _controller() {
  final client = ApiClient();
  return PlaybackController(
    libraryApi: LibraryApi(client),
    transcodeApi: TranscodeApi(client),
    authApi: AuthApi(client),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'The Series Has Landed',
    catalogDuration: 1320,
    isTranscode: true,
    hevc: false,
    subtitles: const [],
    preferredLanguages: const [],
    prefs: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detaching from the host activity releases the player', () {
    var detached = 0;
    final c = _controller()..onHostDetached = () => detached++;
    addTearDown(c.dispose);

    c.didChangeAppLifecycleState(AppLifecycleState.detached);

    expect(detached, 1);
  });

  test('backgrounding and floating in PiP do not', () {
    var detached = 0;
    final c = _controller()..onHostDetached = () => detached++;
    addTearDown(c.dispose);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.resumed,
    ]) {
      c.didChangeAppLifecycleState(state);
    }

    expect(detached, 0);
  });

  test('teardown runs once, however the player leaves', () {
    var detached = 0;
    final c = _controller()..onHostDetached = () => detached++;

    c.didChangeAppLifecycleState(AppLifecycleState.detached);
    // A relaunch re-attaches to the same engine, so the pop the callback asks
    // for can land long after — and a second detach can arrive before it does.
    c.didChangeAppLifecycleState(AppLifecycleState.detached);
    c.dispose();

    expect(detached, 1);
  });
}
