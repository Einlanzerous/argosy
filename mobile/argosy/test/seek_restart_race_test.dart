import 'dart:async';

import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two seeks inside one transcode restart used to run two restarts side by side
/// (ARGY-260): one killed the other's session and reported a bogus "transcoder"
/// error, or both POSTed and the loser's source replaced the winner's while
/// `baseOffset` pointed at the winner, leaking a session. The newest seek must
/// win and leave exactly one session alive.
///
/// The fake server mirrors the real one's id rule: ids are deterministic in
/// the floor of startAt, and POSTing a live id joins it.
class _Server extends TranscodeApi {
  _Server() : super(ApiClient());

  final alive = <String>{};
  final starts = <double>[];
  final stops = <String>[];

  /// While non-null, DELETEs wait on it.
  Completer<void>? stopGate;

  /// POSTs at these startAts wait here, after the server has made the session.
  final startGates = <double, Completer<void>>{};

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    final at = transcodeStartRequest?.startAt ?? 0;
    starts.add(at);
    await Future<void>.delayed(Duration.zero);
    final id = 's${at.floor()}';
    alive.add(id);
    final g = startGates[at];
    if (g != null) await g.future;
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
  }) async {
    stops.add(sessionId);
    final gate = stopGate;
    if (gate != null) await gate.future;
    alive.remove(sessionId);
  }
}

class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  final watched = <String>[];

  @override
  Future<PlayState?> setWatched(
    String id,
    WatchedUpdate watchedUpdate, {
    Future<void>? abortTrigger,
  }) async {
    watched.add(id);
    return null;
  }
}

class _Rig {
  _Rig() {
    c = PlaybackController(
      libraryApi: library,
      transcodeApi: server,
      authApi: AuthApi(ApiClient()),
      baseUrl: 'http://localhost',
      token: null,
      itemId: 'item-1',
      title: 'Scrubs',
      catalogDuration: 1440,
      isTranscode: true,
      hevc: false,
      hevcHardware: false,
      subtitles: const [],
      preferredLanguages: const [],
      prefs: null,
    );
    c.debugProbe = (url, cancelled) async {
      final g = probeGates[url];
      if (g != null) await g.future;
      return true;
    };
    c.debugAttach = (url) async => attached.add(url);
  }

  final server = _Server();
  final library = _Library();
  late final PlaybackController c;
  final probeGates = <String, Completer<void>>{};
  final attached = <String>[];

  void openGates() {
    for (final g in probeGates.values) {
      if (!g.isCompleted) g.complete();
    }
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Plays [seconds] of forward progress, a progress event every half second.
void _play(PlaybackController c, double seconds) {
  // The first progress after a seek only anchors the playhead.
  c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress));
  for (var t = 0.0; t < seconds; t += 0.5) {
    c.baseOffset += 0.5;
    c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress));
  }
}

class _Clock {
  DateTime now = DateTime(2026, 10, 25);
}

/// Runs the Up Next countdown forward [seconds] on a manual clock, 250ms a tick.
void _tick(PlaybackController c, _Clock clock, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.25) {
    clock.now = clock.now.add(const Duration(milliseconds: 250));
    c.maybeAdvance();
    c.debugTickUpNext();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a second seek while the first awaits the playlist wins', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    r.probeGates['http://localhost/p/s100'] = Completer();
    r.probeGates['http://localhost/p/s200'] = Completer();

    final a = r.c.seekTo(100);
    await _settle();
    final b = r.c.seekTo(200);
    await _settle();
    r.openGates();
    await Future.wait([a, b]);

    expect(r.server.alive, {'s200'});
    expect(r.attached, ['http://localhost/p/s200']);
    expect(r.c.baseOffset, 200);
    expect(r.c.position, 200);
    expect(r.c.fatalError, isFalse);
    expect(r.c.errorMessage, isNull);
    expect(r.c.starting, isFalse);
  });

  test('a second seek while the first awaits the stop does not leak', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    await r.c.seekTo(50);
    expect(r.server.alive, {'s50'});

    r.server.stopGate = Completer();
    final a = r.c.seekTo(100);
    await _settle();
    final b = r.c.seekTo(200);
    await _settle();
    // B must be waiting on A's DELETE, not POSTing into it.
    expect(r.server.starts, [50.0]);
    r.server.stopGate!.complete();
    await Future.wait([a, b]);

    expect(r.server.starts, [50.0, 200.0]);
    expect(r.server.alive, {'s200'});
    expect(r.attached.last, 'http://localhost/p/s200');
    expect(r.c.baseOffset, 200);
    expect(r.c.fatalError, isFalse);
    expect(r.c.errorMessage, isNull);
    expect(r.c.starting, isFalse);
  });

  test(
    'a superseded restart does not unmask errors for the live one',
    () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      r.probeGates['http://localhost/p/s100'] = Completer();
      r.probeGates['http://localhost/p/s200'] = Completer();
      final a = r.c.seekTo(100);
      await _settle();
      final b = r.c.seekTo(200);
      await _settle();
      r.probeGates['http://localhost/p/s100']!.complete();
      await a;
      expect(r.c.starting, isTrue);
      r.openGates();
      await b;
      expect(r.c.starting, isFalse);
    },
  );

  test('position stays on the target during the swap', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    await r.c.seekTo(600);
    expect(r.c.baseOffset, 600);

    r.probeGates['http://localhost/p/s300'] = Completer();
    final f = r.c.seekTo(300);
    await _settle();
    // Not 300 + the old source's relative position, and the old base is kept
    // until the new source is up.
    expect(r.c.position, 300);
    expect(r.c.baseOffset, 600);
    r.openGates();
    await f;
    expect(r.c.position, 300);
    expect(r.c.baseOffset, 300);
  });

  test('finished right behind a seek does not finish the episode', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    await r.c.seekTo(100);

    // The plugin posts seekTo then finished for a target past its duration.
    r.c
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo))
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    expect(r.c.debugFinished, isFalse);

    // Once the viewer has played on from the seek, a real finish counts again
    // (ARGY-261: a progress event with no forward motion is not playing).
    r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress));
    r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    expect(r.c.debugFinished, isFalse);
    _play(r.c, PlaybackController.upNextArmSeconds.toDouble());
    r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    expect(r.c.debugFinished, isTrue);
  });

  test('finished while a restart is in flight is ignored', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    r.probeGates['http://localhost/p/s100'] = Completer();
    final f = r.c.seekTo(100);
    await _settle();
    r.c
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress))
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    expect(r.c.debugFinished, isFalse);
    r.openGates();
    await f;
  });

  test('a real end right behind a seek to the end still finishes', () async {
    final r = _Rig();
    addTearDown(r.c.dispose);
    await r.c.seekTo(5000); // clamps to catalogDuration (1440)
    expect(r.c.position, 1440);

    r.c
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo))
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    expect(r.c.debugFinished, isTrue);
  });

  test(
    'revisiting a stopped second and being superseded does not leak',
    () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      await r.c.seekTo(100); // session X = s100
      await r.c.seekTo(500); // X stopped
      expect(r.server.alive, {'s500'});

      // Back to the same second: the POST hands out X again, and is held.
      r.server.startGates[100] = Completer();
      final back = r.c.seekTo(100);
      await _settle();
      expect(r.server.alive, {'s100'});
      final away = r.c.seekTo(900);
      await _settle();
      r.server.startGates[100]!.complete();
      await Future.wait([back, away]);

      expect(r.server.alive, {'s900'});
      expect(r.c.baseOffset, 900);
    },
  );

  group('Up Next after a manual seek (ARGY-261)', () {
    // 30s from the end of 1440s: inside the 40s window, ~98%.
    const inWindow = 1410.0;

    ({_Rig r, _Clock clock, List<int> advanced}) rig() {
      final r = _Rig();
      addTearDown(r.c.dispose);
      final clock = _Clock();
      final advanced = <int>[];
      r.c
        ..nextEpisode = OnDeckItem(
          id: 'next-1',
          seriesId: 's',
          seriesTitle: 'Scrubs',
          seasonNumber: 1,
          episodeNumber: 2,
        )
        ..debugNow = (() => clock.now)
        ..debugPlaying = true
        ..onAdvance = () => advanced.add(1);
      return (r: r, clock: clock, advanced: advanced);
    }

    test('a seek into the window opens the card but holds the countdown',
        () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      t.r.c.maybeAdvance();
      expect(t.r.c.upNextOpen, isTrue);
      expect(t.r.c.upNextHeld, isTrue);

      _tick(t.r.c, t.clock, 20);
      expect(t.advanced, isEmpty);
      expect(t.r.c.upNextCountdown, PlaybackController.upNextCountdownSeconds);
      expect(t.r.c.upNextOpen, isTrue);
    });

    test('five seconds of playback arms it, and then it runs', () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      t.r.c.maybeAdvance();
      _play(t.r.c, 4);
      expect(t.r.c.upNextHeld, isTrue);
      _play(t.r.c, 1);
      expect(t.r.c.upNextHeld, isFalse);

      _tick(t.r.c, t.clock, 14);
      expect(t.advanced, isEmpty);
      _tick(t.r.c, t.clock, 2);
      expect(t.advanced, [1]);
    });

    test('a paused player accrues nothing', () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      for (var i = 0; i < 40; i++) {
        t.r.c.handlePlayerEvent(
          BetterPlayerEvent(BetterPlayerEventType.progress),
        );
      }
      expect(t.r.c.upNextHeld, isTrue);
    });

    test('a second seek re-holds', () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      _play(t.r.c, 5);
      expect(t.r.c.upNextHeld, isFalse);

      await t.r.c.seekTo(inWindow + 5);
      t.r.c.maybeAdvance();
      expect(t.r.c.upNextOpen, isTrue);
      expect(t.r.c.upNextHeld, isTrue);
      _tick(t.r.c, t.clock, 20);
      expect(t.advanced, isEmpty);
    });

    test('playing into the window still counts down at once', () {
      final t = rig();
      t.r.c.baseOffset = 1440.0 - 41;
      t.r.c.maybeAdvance();
      expect(t.r.c.upNextOpen, isFalse);
      _play(t.r.c, 1);
      t.r.c.maybeAdvance();
      expect(t.r.c.upNextOpen, isTrue);
      expect(t.r.c.upNextHeld, isFalse);

      _tick(t.r.c, t.clock, 16);
      expect(t.advanced, [1]);
    });

    test('finished right after a seek marks nothing and advances nothing',
        () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
      _play(t.r.c, 2);
      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
      expect(t.r.c.debugFinished, isFalse);
      expect(t.advanced, isEmpty);
    });

    test('a real end right behind a seek to the end finishes and counts down',
        () async {
      final t = rig();
      await t.r.c.seekTo(5000); // clamps to the 1440s catalog end
      t.r.c.maybeAdvance();
      expect(t.r.c.upNextOpen, isTrue);
      expect(t.r.c.upNextHeld, isTrue);

      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo));
      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
      expect(t.r.c.debugFinished, isTrue);
      expect(t.r.library.watched, ['item-1']);
      // The card was up, so the countdown owns the roll-over and is no longer held.
      expect(t.r.c.upNextHeld, isFalse);
      expect(t.advanced, isEmpty);
      _tick(t.r.c, t.clock, 16);
      expect(t.advanced, [1]);
    });

    test('finished far from the end with no playback marks nothing', () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
      expect(t.r.c.debugFinished, isFalse);
      expect(t.r.library.watched, isEmpty);
    });

    test('finished after enough playback is the real end', () async {
      final t = rig();
      await t.r.c.seekTo(inWindow);
      _play(t.r.c, 5);
      t.r.c.handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
      expect(t.r.c.debugFinished, isTrue);
    });
  });
}
