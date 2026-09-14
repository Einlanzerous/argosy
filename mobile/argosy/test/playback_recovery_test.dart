import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transcode session can vanish under the player: the idle reaper takes it
/// after a long pause, or someone stops it server-side. Its segments then 404,
/// and the player used to die with "Playback stopped unexpectedly." (ARGY-239).
/// It now restarts the session at the playhead, within a budget that latches.
///
/// With no player attached, `position` collapses to `baseOffset`, so these set
/// the playhead by setting that.
class _Transcoder extends TranscodeApi {
  _Transcoder() : super(ApiClient());

  final starts = <double>[];

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    starts.add(transcodeStartRequest?.startAt ?? 0);
    // No session back, as from a server at capacity. Whether a restart was
    // attempted, and from where, is all these need.
    return null;
  }
}

PlaybackController _controller(
  TranscodeApi transcodeApi, {
  bool isTranscode = true,
  String? localPath,
}) {
  final client = ApiClient();
  return PlaybackController(
    libraryApi: LibraryApi(client),
    transcodeApi: transcodeApi,
    authApi: AuthApi(client),
    baseUrl: 'http://localhost',
    token: null,
    itemId: 'item-1',
    title: 'The Blade and Me',
    catalogDuration: 1440,
    isTranscode: isTranscode,
    hevc: false,
    subtitles: const [],
    preferredLanguages: const [],
    prefs: null,
    localPath: localPath,
  );
}

final _error = BetterPlayerEvent(BetterPlayerEventType.exception);

/// Lets the deferred restart run and its requests settle.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a dead session restarts at the playhead instead of failing', () async {
    final t = _Transcoder();
    final c = _controller(t)..baseOffset = 612;
    addTearDown(c.dispose);

    // The plugin re-posts the exception on every value change while the error
    // stands, so one reaped session reports itself several times.
    c
      ..handlePlayerEvent(_error)
      ..handlePlayerEvent(_error)
      ..handlePlayerEvent(_error);
    expect(c.fatalError, isFalse);
    await _settle();

    expect(t.starts, [612.0]);
  });

  test('restarts that never play give up at the cap', () async {
    final t = _Transcoder();
    final c = _controller(t)..baseOffset = 612;
    addTearDown(c.dispose);

    for (var i = 0; i < 4; i++) {
      c.handlePlayerEvent(_error);
      await _settle();
    }

    expect(t.starts, [612.0, 612.0]);
    expect(c.fatalError, isTrue);
  });

  test('direct play has no session to restart', () {
    final t = _Transcoder();
    final c = _controller(t, isTranscode: false);
    addTearDown(c.dispose);

    c.handlePlayerEvent(_error);

    expect(t.starts, isEmpty);
    expect(c.errorMessage, 'Playback stopped unexpectedly.');
  });

  test('neither does a stowed file', () {
    final t = _Transcoder();
    final c = _controller(t, localPath: '/data/stow/bleach-s17e22.mkv');
    addTearDown(c.dispose);

    c.handlePlayerEvent(_error);

    expect(t.starts, isEmpty);
    expect(c.fatalError, isTrue);
  });

  test('a host detached before the restart runs does not start one', () async {
    final t = _Transcoder();
    final c = _controller(t)..baseOffset = 612;
    addTearDown(c.dispose);

    c.handlePlayerEvent(_error);
    // The activity goes (ARGY-190) between the error and the deferred restart.
    // Nothing would ever touch or stop a session started now.
    c.didChangeAppLifecycleState(AppLifecycleState.detached);
    await _settle();

    expect(t.starts, isEmpty);
  });

  test('an error after teardown is ignored', () async {
    final t = _Transcoder();
    final c = _controller(t)..baseOffset = 612;
    addTearDown(c.dispose);

    c
      ..didChangeAppLifecycleState(AppLifecycleState.detached)
      ..handlePlayerEvent(_error);
    await _settle();

    expect(t.starts, isEmpty);
    expect(c.fatalError, isFalse);
  });
}
