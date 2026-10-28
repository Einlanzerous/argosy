import 'dart:io';

import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy/features/player/session_recovery.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// A network cut near the end of an episode wedged the phone player (ARGY-283):
/// ten transcode restarts at `startAt=44842.96` into a 1355s episode, a Retry
/// that re-sent the same offset, an Up Next card over a dead stream, and a
/// heartbeat that reported the garbage position — which marked the episode
/// watched and put Continue at 0:00.
///
/// The arithmetic: a restart that failed before the source swap still committed
/// its target into `baseOffset`, while the plugin went on holding the old source
/// and its stale relative position (~220s, the buffered tail). So the playhead
/// read 220s further on at every failed restart; the recovery budget mistook
/// that for forward progress and re-armed; and the offset walked out of the
/// episode 220s at a time for as long as the link was down.
///
/// These drive the controller the way the plugin does — events in, transcode
/// calls out — with the plugin's value supplied through [debugVideoValue].
const _duration = 1355.872;
const _sessionStart = 1046.7274135568748;

/// The relative position the stalled player was frozen at: 55 four-second
/// segments, the last of them not quite rendered out.
const _staleRel = 220.082;
const _stallAbs = _sessionStart + _staleRel;

class _Server extends TranscodeApi {
  _Server() : super(ApiClient());

  /// Airplane mode: every request dies on the socket.
  bool online = false;

  final starts = <double>[];
  final stops = <String>[];

  @override
  Future<TranscodeSession?> startTranscode(
    String itemId, {
    TranscodeStartRequest? transcodeStartRequest,
    Future<void>? abortTrigger,
  }) async {
    final at = transcodeStartRequest?.startAt ?? 0;
    starts.add(at);
    await Future<void>.delayed(Duration.zero);
    if (!online) throw const SocketException('Network is unreachable');
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
  }) async {
    stops.add(sessionId);
    if (!online) throw const SocketException('Network is unreachable');
  }
}

class _Library extends LibraryApi {
  _Library() : super(ApiClient());

  final reports = <ProgressUpdate>[];
  final watched = <String>[];

  @override
  Future<PlayState?> reportProgress(
    String itemId,
    ProgressUpdate progressUpdate, {
    Future<void>? abortTrigger,
  }) async {
    reports.add(progressUpdate);
    return null;
  }

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
  _Rig({bool withNext = false}) {
    c = PlaybackController(
      libraryApi: library,
      transcodeApi: server,
      authApi: AuthApi(ApiClient()),
      baseUrl: 'http://localhost',
      token: null,
      itemId: 'item-1',
      title: 'Futurama s03e05',
      catalogDuration: _duration,
      isTranscode: true,
      hevc: true,
      hevcHardware: true,
      subtitles: const [],
      preferredLanguages: const [],
      prefs: null,
    );
    c.debugProbe = (url, cancelled) async => true;
    // The plugin resets its value when it takes a new source, so a swapped-in
    // session starts at relative zero.
    c.debugAttach = (url) async {
      attached.add(url);
      c.debugVideoValue = _value(0);
    };
    if (withNext) {
      c.nextEpisode = OnDeckItem(
        id: 'next-1',
        seriesId: 'series-1',
        seriesTitle: 'Futurama',
        seasonNumber: 3,
        episodeNumber: 6,
      );
    }
    c.onAdvance = () => advanced++;
    // The player as the stall left it: the session started at 1046.7s and the
    // plugin's clock is frozen at the end of the buffered tail.
    c.baseOffset = _sessionStart;
    c.debugVideoValue = _value(_staleRel);
  }

  final server = _Server();
  final library = _Library();
  final attached = <String>[];
  late final PlaybackController c;
  int advanced = 0;

  /// One `exception`, as the plugin re-posts it on every value change while
  /// the error stands, followed by the `progress` the same change produces.
  Future<void> failOnce() async {
    c.handlePlayerEvent(_error);
    await settle();
    c.handlePlayerEvent(_progress);
    await settle();
  }

  /// Enough failures to spend the recovery budget — two restarts and the
  /// give-up — and land on the error overlay, the way the incident did before
  /// the first Retry.
  Future<void> failUntilFatal() async {
    for (var i = 0; i <= SessionRecovery.maxAttempts; i++) {
      await failOnce();
    }
    expect(c.fatalError, isTrue);
    expect(c.debugRecovery.attempts, SessionRecovery.maxAttempts);
  }
}

VideoPlayerValue _value(double relSeconds) => VideoPlayerValue(
  duration: const Duration(seconds: 309),
  position: Duration(milliseconds: (relSeconds * 1000).round()),
);

final _error = BetterPlayerEvent(BetterPlayerEventType.exception);
final _progress = BetterPlayerEvent(BetterPlayerEventType.progress);
final _pause = BetterPlayerEvent(BetterPlayerEventType.pause);
final _finished = BetterPlayerEvent(BetterPlayerEventType.finished);

/// Lets a deferred restart run and its requests settle.
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a restart that fails before the source swap', () {
    test('keeps the playhead where the player actually is', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);

      await r.failOnce();

      expect(r.server.starts, [closeTo(_stallAbs, 0.001)]);
      // Not committed: the plugin still holds the old source, so the offset
      // it is measured from must not move.
      expect(r.c.baseOffset, _sessionStart);
      expect(r.c.position, closeTo(_stallAbs, 0.001));
      expect(r.c.starting, isFalse);
    });

    test('never walks the restart offset out of the episode', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);

      // The incident's loop: error, failed restart, progress, again — for as
      // long as the link stays down.
      for (var i = 0; i < 12; i++) {
        await r.failOnce();
      }

      for (final at in r.server.starts) {
        expect(at, closeTo(_stallAbs, 0.001));
        expect(r.c.isSanePosition(at), isTrue);
      }
      // And the budget is not re-armed by the restart's own arithmetic: two
      // restarts, then the error overlay — not one every second.
      expect(r.server.starts, hasLength(SessionRecovery.maxAttempts));
      expect(r.c.fatalError, isTrue);
      expect(r.c.baseOffset, _sessionStart);
    });
  });

  group('a position outside the title', () {
    test('never reaches a transcode start', () async {
      for (final (label, prepare) in <(String, void Function(_Rig))>[
        (
          'twelve hours in',
          (r) => r.c.debugVideoValue = _value(43796.234),
        ),
        ('negative', (r) => r.c.baseOffset = -300),
        ('NaN', (r) => r.c.baseOffset = double.nan),
        ('infinite', (r) => r.c.baseOffset = double.infinity),
      ]) {
        final r = _Rig();
        addTearDown(r.c.dispose);
        // A believable reading first, as a healthy stream would have given.
        r.c.debugVideoValue = _value(200);
        r.c.handlePlayerEvent(_progress);
        expect(r.c.debugLastGoodPosition, closeTo(_sessionStart + 200, 0.001));

        prepare(r);
        expect(r.c.isSanePosition(r.c.position), isFalse, reason: label);

        await r.failOnce();

        expect(
          r.server.starts,
          [closeTo(_sessionStart + 200, 0.001)],
          reason: '$label: the restart falls back to the last good position',
        );
        expect(
          r.c.debugLastGoodPosition,
          closeTo(_sessionStart + 200, 0.001),
          reason: '$label: the bad reading did not become the last good one',
        );
      }
    });

    test('is not believed by the recovery budget either', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      await r.failOnce();
      expect(r.c.debugRecovery.attempts, 1);

      // A garbage reading far "ahead" of the restart point used to read as
      // forward progress and reset the budget.
      r.c.debugVideoValue = _value(43796.234);
      r.c.handlePlayerEvent(_progress);
      expect(r.c.debugRecovery.attempts, 1);
    });
  });

  group('Retry', () {
    test('starts a fresh session at the last good position', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      await r.failUntilFatal();
      expect(r.c.fatalError, isTrue);
      expect(r.server.starts, hasLength(2));
      expect(r.c.debugRecovery.attempts, SessionRecovery.maxAttempts);

      r.server.online = true;
      await r.c.retry();
      await settle();

      // Where the viewer was — not the session's start (baseOffset, 1046.7),
      // and not an offset that had already failed.
      expect(r.server.starts, hasLength(3));
      expect(r.server.starts.last, closeTo(_stallAbs, 0.001));
      expect(r.c.fatalError, isFalse);
      expect(r.c.starting, isFalse);
      expect(r.c.debugHasSession, isTrue);
      expect(r.attached, hasLength(1));
      // The swap happened, so the new offset is committed and the playhead
      // continues from it.
      expect(r.c.baseOffset, closeTo(_stallAbs, 0.001));
      expect(r.c.position, closeTo(_stallAbs, 0.001));
      // A fresh budget, latch cleared.
      expect(r.c.debugRecovery.attempts, 0);
      expect(r.c.debugRecovery.inFlight, isFalse);
    });

    test('from a still-dead link fails cleanly and stays retryable', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      await r.failUntilFatal();

      await r.c.retry();
      await settle();
      expect(r.c.fatalError, isTrue);
      expect(r.server.starts.last, closeTo(_stallAbs, 0.001));
      expect(r.c.baseOffset, _sessionStart);

      // The link comes back; the next Retry succeeds from the same place.
      r.server.online = true;
      await r.c.retry();
      await settle();
      expect(r.c.fatalError, isFalse);
      expect(r.server.starts.last, closeTo(_stallAbs, 0.001));
    });
  });

  group('Up Next', () {
    test('does not open over a broken stream', () async {
      final r = _Rig(withNext: true);
      addTearDown(r.c.dispose);
      // Inside the window, as the end of the buffered tail may well be.
      r.c.baseOffset = _duration - 30 - _staleRel;
      await r.failUntilFatal();
      expect(r.c.fatalError, isTrue);

      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isFalse);
      r.c.debugTickUpNext();
      expect(r.advanced, 0);
    });

    test('closes when the stream breaks and does not re-arm on retry', () async {
      final r = _Rig(withNext: true);
      addTearDown(r.c.dispose);
      r.c.baseOffset = _duration - 30 - _staleRel;
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isTrue, reason: 'a healthy player in the window');

      await r.failOnce();
      // The failure itself takes the card down, before any repaint tick.
      expect(r.c.upNextOpen, isFalse);
      await r.failUntilFatal();
      // The repaint ticker keeps calling this; it stays down.
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isFalse);

      final retry = r.c.retry(); // still offline
      // Mid-restart (the POST is in flight) the ticker finds nothing to open.
      r.c.maybeAdvance();
      expect(r.c.starting, isTrue);
      expect(r.c.upNextOpen, isFalse);
      await retry;
      await settle();
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isFalse);
      expect(r.advanced, 0);

      // Only once playback is genuinely back inside the window does it return,
      // with a full countdown.
      r.server.online = true;
      await r.c.retry();
      await settle();
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isTrue);
      expect(r.c.upNextCountdown, PlaybackController.upNextCountdownSeconds);
    });

    test('an impossible position opens nothing', () {
      final r = _Rig(withNext: true);
      addTearDown(r.c.dispose);
      r.c.debugVideoValue = _value(43796.234);
      r.c.maybeAdvance();
      expect(r.c.upNextOpen, isFalse);
    });

    test('finished at an impossible position marks nothing and advances nothing',
        () async {
      final r = _Rig(withNext: true);
      addTearDown(r.c.dispose);
      r.c.debugVideoValue = _value(43796.234);

      r.c.handlePlayerEvent(_finished);
      await settle();

      expect(r.c.debugFinished, isFalse);
      expect(r.library.watched, isEmpty);
      expect(r.library.reports, isEmpty);
      expect(r.advanced, 0);
    });

    test('finished from a broken stream is not the episode ending', () async {
      final r = _Rig(withNext: true);
      addTearDown(r.c.dispose);
      await r.failUntilFatal();

      // An empty session ends the instant it opens.
      r.c.debugVideoValue = _value(0);
      r.c.handlePlayerEvent(_finished);
      await settle();

      expect(r.c.debugFinished, isFalse);
      expect(r.library.watched, isEmpty);
      expect(r.advanced, 0);
    });
  });

  group('progress reports', () {
    test('a healthy pause reports the real position', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      r.c.handlePlayerEvent(_pause);
      await settle();
      expect(r.library.reports, hasLength(1));
      expect(r.library.reports.single.positionSeconds, closeTo(_stallAbs, 0.001));
      expect(r.library.reports.single.durationSeconds, _duration);
    });

    test('nothing is reported from the fatal state', () async {
      final r = _Rig(); // disposed below, as the leaving-the-screen step
      await r.failUntilFatal();
      r.library.reports.clear();

      // The paused keepalive and the plugin's pause echo both flush.
      r.c.handlePlayerEvent(_pause);
      await settle();
      expect(r.library.reports, isEmpty);

      // Leaving the screen does not clobber the server's resume point with a
      // dead player's position either.
      r.c.dispose();
      await settle();
      expect(r.library.reports, isEmpty);
    });

    test('an impossible position is never reported', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      r.c.debugVideoValue = _value(43796.234);

      r.c.handlePlayerEvent(_pause);
      await settle();
      expect(r.library.reports, isEmpty);

      r.c.baseOffset = double.nan;
      r.c.handlePlayerEvent(_pause);
      await settle();
      expect(r.library.reports, isEmpty);
    });

    test('a position inside the title still goes out', () async {
      final r = _Rig();
      addTearDown(r.c.dispose);
      // One restart in flight (not fatal yet): the playhead is the believable
      // stall point, and keeping the server current with it is right.
      r.c.handlePlayerEvent(_error);
      await settle();
      r.c.handlePlayerEvent(_pause);
      await settle();
      expect(r.library.reports.map((p) => p.positionSeconds),
          everyElement(closeTo(_stallAbs, 0.001)));
    });
  });
}
