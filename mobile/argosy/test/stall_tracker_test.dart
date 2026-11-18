import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:argosy/features/player/playback_controller.dart';
import 'package:argosy/features/player/stall_tracker.dart';
import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARGY-313: a rebuffer is reported once, tagged with its cause; the start-up
/// buffer and the buffer behind a source swap are not stalls; a flapping link
/// cannot spam the server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StallTracker', () {
    late DateTime clock;
    late List<StallReport> reports;
    late StallTracker t;

    void tick(int ms) => clock = clock.add(Duration(milliseconds: ms));

    setUp(() {
      clock = DateTime(2026, 11, 17, 12);
      reports = [];
      t = StallTracker(onReport: reports.add, now: () => clock);
    });

    void stall(int ms, {double pos = 10, double? ahead}) {
      t.bufferingStart(positionSeconds: pos, bufferedAheadSeconds: ahead);
      tick(ms);
      t.bufferingEnd();
    }

    test('pairs a start with its end into one report', () {
      t.arm();
      stall(1500, pos: 42, ahead: 3.5);

      expect(reports, hasLength(1));
      expect(reports.single.duration, const Duration(milliseconds: 1500));
      expect(reports.single.positionSeconds, 42);
      expect(reports.single.bufferedAheadSeconds, 3.5);
      expect(reports.single.ended, isTrue);
      expect(reports.single.cause, StallCause.play);
    });

    test('an end with no start, and a second start, report nothing extra', () {
      t.arm();
      t.bufferingEnd();
      expect(reports, isEmpty);

      t.bufferingStart(positionSeconds: 1);
      tick(500);
      t.bufferingStart(positionSeconds: 99); // ignored: one stall is open
      tick(500);
      t.bufferingEnd();
      expect(reports, hasLength(1));
      expect(reports.single.positionSeconds, 1);
      expect(reports.single.duration, const Duration(seconds: 1));
    });

    test('the initial start-up buffer is not a stall', () {
      // Never armed: nothing has played yet.
      stall(4000);
      expect(reports, isEmpty);
    });

    test('a swap or restart disarms until playback is seen again', () {
      t.arm();
      t.disarm(); // a transcode restart began
      stall(4000);
      expect(reports, isEmpty);

      t.arm();
      tick(5000);
      stall(900);
      expect(reports, hasLength(1));
    });

    test('a stall open when a swap begins is dropped, not reported', () {
      t.arm();
      t.bufferingStart(positionSeconds: 5);
      tick(3000);
      t.disarm();
      t.arm();
      t.bufferingEnd();
      expect(reports, isEmpty);
    });

    test('a seek within the window tags the stall as a seek', () {
      t.arm();
      t.noteSeek();
      tick(1000);
      stall(800);
      expect(reports.single.cause, StallCause.seek);
    });

    test('a resume within the window tags it resume; a seek beats it', () {
      t.arm();
      t.noteResume();
      tick(1000);
      stall(800);
      expect(reports.last.cause, StallCause.resume);

      tick(3000);
      t.noteResume();
      t.noteSeek();
      stall(800);
      expect(reports.last.cause, StallCause.seek);
    });

    test('a seek or resume long ago is not blamed', () {
      t.arm();
      t.noteSeek();
      t.noteResume();
      tick(20000);
      stall(800);
      expect(reports.single.cause, StallCause.play);
    });

    test('stalls under the minimum are coalesced away', () {
      t.arm();
      stall(100);
      expect(reports, isEmpty);
      stall(250);
      expect(reports, hasLength(1));
    });

    test('a flapping link sends at most one report per interval', () {
      t.arm();
      for (var i = 0; i < 6; i++) {
        stall(400);
        tick(100);
      }
      // 6 stalls in ~3s: the first goes, then one more after 2s has passed.
      expect(reports.length, lessThanOrEqualTo(2));
      expect(reports.length, greaterThanOrEqualTo(1));

      tick(2500);
      final before = reports.length;
      stall(400);
      expect(reports, hasLength(before + 1));
    });

    test('leaving mid-stall reports the time so far with ended: false', () {
      t.arm();
      t.bufferingStart(positionSeconds: 77);
      tick(2200);
      t.abandon();

      expect(reports, hasLength(1));
      expect(reports.single.ended, isFalse);
      expect(reports.single.duration, const Duration(milliseconds: 2200));
      expect(reports.single.positionSeconds, 77);

      // Nothing more once abandoned.
      t.bufferingEnd();
      expect(reports, hasLength(1));
      expect(t.armed, isFalse);
    });

    test('leaving with no open stall reports nothing', () {
      t.arm();
      t.abandon();
      expect(reports, isEmpty);
    });
  });

  group('PlaybackController stall wiring', () {
    late PlaybackController c;
    late List<PlaybackEvent> sent;

    BetterPlayerEvent ev(BetterPlayerEventType type) => BetterPlayerEvent(type);

    Future<void> realMs(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    void playing() {
      c.debugVideoValue = VideoPlayerValue(
        duration: const Duration(seconds: 309),
        position: const Duration(seconds: 100),
        isPlaying: true,
      );
      c.handlePlayerEvent(ev(BetterPlayerEventType.progress));
    }

    setUp(() {
      sent = [];
      c = PlaybackController(
        libraryApi: LibraryApi(ApiClient()),
        transcodeApi: TranscodeApi(ApiClient()),
        authApi: AuthApi(ApiClient()),
        baseUrl: 'http://localhost',
        token: null,
        itemId: 'item-1',
        title: 'Futurama s03e05',
        catalogDuration: 1355.872,
        isTranscode: true,
        hevc: true,
        hevcHardware: true,
        subtitles: const [],
        preferredLanguages: const [],
        prefs: null,
      );
      c.baseOffset = 500;
      c.debugSessionId = 's500';
      c.debugStallSink = sent.add;
      addTearDown(() {
        c.debugSessionId = null;
        c.debugStallSink = null;
        c.dispose();
      });
    });

    test(
      'a mid-play rebuffer sends one event with absolute position',
      () async {
        playing();
        c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
        await realMs(300);
        c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingEnd));

        expect(sent, hasLength(1));
        final e = sent.single;
        expect(e.kind, PlaybackEventKindEnum.stall);
        expect(e.cause, PlaybackEventCauseEnum.play);
        expect(e.positionSeconds, closeTo(600, 0.001)); // 500 + 100
        expect(e.durationMs, greaterThanOrEqualTo(250));
        expect(e.sessionId, 's500');
        expect(e.ended, isTrue);
      },
    );

    test('buffering before any real playback is not reported', () async {
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
      await realMs(300);
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingEnd));
      expect(sent, isEmpty);
    });

    test('buffering while starting (a swap) is not reported', () async {
      playing();
      c.starting = true;
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
      await realMs(300);
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingEnd));
      expect(sent, isEmpty);
    });

    test('a seek just before the stall tags it seek', () async {
      playing();
      c.debugStalls.noteSeek();
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
      await realMs(300);
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingEnd));
      expect(sent.single.cause, PlaybackEventCauseEnum.seek);
    });

    test('leaving mid-stall sends ended: false on teardown', () async {
      playing();
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
      await realMs(300);
      c.debugSessionId = null;
      c.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(sent, hasLength(1));
      expect(sent.single.ended, isFalse);
    });

    test('a failing send never reaches playback', () async {
      c.debugStallSink = null; // real client, nothing listening on localhost
      playing();
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingStart));
      await realMs(300);
      c.handlePlayerEvent(ev(BetterPlayerEventType.bufferingEnd));
      await realMs(200);
      expect(c.fatalError, isFalse);
    }, skip: Platform.isWindows);
  });
}
