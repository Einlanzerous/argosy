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

class _Rig {
  _Rig() {
    c = PlaybackController(
      libraryApi: LibraryApi(ApiClient()),
      transcodeApi: server,
      authApi: AuthApi(ApiClient()),
      baseUrl: 'http://localhost',
      token: null,
      itemId: 'item-1',
      title: 'Scrubs',
      catalogDuration: 1440,
      isTranscode: true,
      hevc: false,
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

    // Once playback progresses, a real finish counts again.
    r.c
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.progress))
      ..handlePlayerEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
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
}
