import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A next-episode lookup that failed at start used to read as "last episode"
/// (ARGY-264): `nextEpisode` stayed null for the whole episode, so no Up Next
/// card and no auto-advance. Only a server answer is terminal now; a failure is
/// retried on the signals that say the server is back, within a bound.
const _duration = 1440.0;
const _inWindow = 1410.0;

class _Transcode extends TranscodeApi {
  _Transcode() : super(ApiClient());

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    final at = transcodeStartRequest?.startAt ?? 0;
    final id = 's${at.floor()}';
    return TranscodeSession(
      id: id,
      itemId: itemId,
      encoder: 'x264',
      method: TranscodeSessionMethodEnum.transcode,
      state: TranscodeSessionStateEnum.running,
      startAt: at,
      startedAt: DateTime.now(),
      playlistUrl: '/p/$id',
      progress: TranscodeProgress(outTimeMs: 0, speed: 1, fps: 30),
    );
  }

  @override
  Future<void> stopTranscode(
    String sessionId, {
    Future<void>? abortTrigger,
  }) async {}
}

final _next = OnDeckItem(
  id: 'next-1',
  seriesId: 's',
  seriesTitle: 'Scrubs',
  seasonNumber: 1,
  episodeNumber: 7,
);

class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  /// Each call takes the next outcome; the last one repeats.
  /// An Exception fails, an ApiException(404) is "no next", an item succeeds.
  List<Object?> outcomes = [Exception('down')];
  int calls = 0;

  @override
  Future<OnDeckItem?> getNextEpisode(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    final i = calls < outcomes.length ? calls : outcomes.length - 1;
    calls++;
    await Future<void>.delayed(Duration.zero);
    final o = outcomes[i];
    if (o is Exception) throw o;
    return o as OnDeckItem?;
  }

  @override
  Future<PlayState?> setWatched(
    String id,
    WatchedUpdate watchedUpdate, {
    Future<void>? abortTrigger,
  }) async => null;
}

class _Clock {
  DateTime now = DateTime(2026, 10, 25);
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
}

class _Rig {
  _Rig({String? localPath}) {
    c = PlaybackController(
      libraryApi: library,
      transcodeApi: _Transcode(),
      authApi: AuthApi(ApiClient()),
      baseUrl: 'http://localhost',
      token: null,
      itemId: 'item-1',
      title: 'Scrubs',
      catalogDuration: _duration,
      isTranscode: true,
      hevc: false,
      hevcHardware: false,
      subtitles: const [],
      preferredLanguages: const [],
      prefs: null,
      localPath: localPath,
    );
    c
      ..debugProbe = ((url, cancelled) async => true)
      ..debugAttach = ((url) async {})
      ..debugNow = (() => clock.now)
      ..debugPlaying = true
      ..onAdvance = () => advanced++;
  }

  final library = _Library();
  final clock = _Clock();
  late final PlaybackController c;
  int advanced = 0;
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Plays [seconds] of forward progress so `finished` counts as a real end.
void _play(PlaybackController c, double seconds) {
  c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress));
  for (var t = 0.0; t < seconds; t += 0.5) {
    c.baseOffset += 0.5;
    c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress));
  }
}

void _finish(PlaybackController c) =>
    c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));

Future<_Rig> _failedAtStart({List<Object?>? then, String? localPath}) async {
  final r = _Rig(localPath: localPath);
  addTearDown(r.c.dispose);
  await r.c.debugLoadNextEpisode();
  if (then != null) r.library.outcomes = [Exception('down'), ...then];
  return r;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a failed lookup opens the card once entering the window retries',
    () async {
      final r = await _failedAtStart(then: [_next]);
      expect(r.c.nextEpisode, isNull);

      // Outside the window nothing is asked.
      r.clock.advance(30);
      r.c.baseOffset = 600;
      r.c.maybeAdvance();
      await _settle();
      expect(r.library.calls, 1);

      r.c.baseOffset = _inWindow;
      r.c.maybeAdvance();
      await _settle();
      expect(r.c.nextEpisode, isNotNull);
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isTrue);
      expect(r.library.calls, 2);
    },
  );

  test('a winning transcode restart retries the lookup', () async {
    final r = await _failedAtStart(then: [_next]);
    r.clock.advance(30);

    await r.c.seekTo(100);
    await _settle();

    expect(r.library.calls, 2);
    expect(r.c.nextEpisode, isNotNull);
  });

  test('a superseded restart does not retry', () async {
    final r = await _failedAtStart(then: [_next]);
    r.clock.advance(30);

    final a = r.c.seekTo(100);
    final b = r.c.seekTo(200);
    await Future.wait([a, b]);
    await _settle();

    // One winner, one retry.
    expect(r.library.calls, 2);
  });

  test(
    'finished retries before deciding there is nothing to advance to',
    () async {
      final r = await _failedAtStart(then: [_next]);
      await r.c.seekTo(_inWindow);
      // No clock advance: the restart's own retry is held back by the gap.
      expect(r.library.calls, 1);
      _play(r.c, 5);
      // Skip the window-entry path: the end of file comes first.
      _finish(r.c);
      await _settle();

      expect(r.library.calls, 2);
      expect(r.advanced, 1);
    },
  );

  test(
    'a lookup that keeps failing is bounded and finished stays put',
    () async {
      final r = await _failedAtStart();
      for (var i = 0; i < 20; i++) {
        r.clock.advance(11);
        r.c.baseOffset = _inWindow;
        r.c.maybeAdvance();
        await _settle();
      }
      expect(r.library.calls, PlaybackController.nextEpisodeMaxAttempts);
      expect(r.c.upNextOpen, isFalse);

      _play(r.c, 5);
      _finish(r.c);
      await _settle();
      // One last try at the end, then it stays on the episode.
      expect(r.library.calls, PlaybackController.nextEpisodeMaxAttempts + 1);
      expect(r.advanced, 0);
      expect(r.c.nextEpisode, isNull);

      _finish(r.c);
      await _settle();
      expect(r.library.calls, PlaybackController.nextEpisodeMaxAttempts + 1);
    },
  );

  test(
    'retries are spaced, and a ticker hammering maybeAdvance is one call',
    () async {
      final r = await _failedAtStart();
      r.c.baseOffset = _inWindow;
      for (var i = 0; i < 50; i++) {
        r.c.maybeAdvance();
        await _settle();
      }
      expect(r.library.calls, 1);

      r.clock.advance(11);
      for (var i = 0; i < 50; i++) {
        r.c.maybeAdvance();
      }
      await _settle();
      expect(r.library.calls, 2);
    },
  );

  test('a 404 is the last episode: never retried', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    r.library.outcomes = [ApiException(404, 'Not found')];
    await r.c.debugLoadNextEpisode();

    r.clock.advance(30);
    await r.c.seekTo(_inWindow);
    r.c.maybeAdvance();
    _play(r.c, 5);
    _finish(r.c);
    await _settle();

    expect(r.library.calls, 1);
    expect(r.c.nextEpisode, isNull);
    expect(r.advanced, 0);
  });

  test('a null answer is terminal too', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    r.library.outcomes = [null];
    await r.c.debugLoadNextEpisode();

    r.clock.advance(30);
    await r.c.seekTo(_inWindow);
    r.c.maybeAdvance();
    await _settle();

    expect(r.library.calls, 1);
  });

  test('offline playback never asks', () async {
    final r = _Rig(localPath: '/tmp/x.mp4');
    addTearDown(r.c.dispose);
    await r.c.debugLoadNextEpisode();
    r.clock.advance(30);
    r.c.baseOffset = _inWindow;
    r.c.maybeAdvance();
    _play(r.c, 5);
    _finish(r.c);
    await _settle();

    expect(r.library.calls, 0);
  });
}
