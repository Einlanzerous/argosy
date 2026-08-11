import 'package:argosy/features/player/argosy_audio_handler.dart';
import 'package:argosy/features/player/media_session_state.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lock-screen session is fed from Dart rather than bound to the ExoPlayer,
/// because playback is transcode-backed and the player's own timeline is
/// relative. These lock down the derivation rules that makes correct (ARGY-87).

const _futurama = NowPlaying(
  id: 'ep-1',
  title: 'The Series Has Landed',
  subtitle: 'Futurama · Season 1, Ep 2',
  durationSeconds: 1320,
);

/// A title the catalog has no runtime for.
const _unknownRuntime = NowPlaying(id: 'x', title: 'Mystery', durationSeconds: 0);

void main() {
  group('media item', () {
    test('an unknown runtime carries no duration at all', () {
      // Duration.zero would render a real — but zero-width — scrubber.
      expect(_unknownRuntime.toMediaItem().duration, isNull);
      expect(_futurama.toMediaItem().duration, const Duration(seconds: 1320));
    });

    test('the two lines land on title and artist', () {
      final item = _futurama.toMediaItem();
      expect(item.title, 'The Series Has Landed');
      expect(item.artist, 'Futurama · Season 1, Ep 2');
    });

    test('a blank artwork url is dropped rather than parsed', () {
      const bare = NowPlaying(
        id: 'x',
        title: 'T',
        durationSeconds: 60,
        artworkUrl: '',
      );
      expect(bare.toMediaItem().artUri, isNull);
    });
  });

  group('playback state', () {
    test('the seek bar is offered only when there is a runtime to scrub', () {
      expect(
        mediaPlaybackState(
          phase: MediaPhase.playing,
          positionSeconds: 10,
          now: _futurama,
        ).systemActions,
        contains(MediaAction.seek),
      );
      expect(
        mediaPlaybackState(
          phase: MediaPhase.playing,
          positionSeconds: 10,
          now: _unknownRuntime,
        ).systemActions,
        isNot(contains(MediaAction.seek)),
      );
    });

    test('anything short of playing reports speed 0', () {
      // System UI extrapolates position from speed and the update timestamp, so
      // a stalled or paused player at speed 1 walks the scrubber past the video.
      for (final phase in [
        MediaPhase.starting,
        MediaPhase.buffering,
        MediaPhase.paused,
        MediaPhase.finished,
      ]) {
        final s = mediaPlaybackState(
          phase: phase,
          positionSeconds: 10,
          now: _futurama,
          speed: 1.5,
        );
        expect(s.speed, 0.0, reason: '$phase should not advance the scrubber');
        expect(s.playing, isFalse, reason: '$phase is not playing');
      }
    });

    test('playing carries the reported rate', () {
      final s = mediaPlaybackState(
        phase: MediaPhase.playing,
        positionSeconds: 10,
        now: _futurama,
        speed: 1.5,
      );
      expect(s.playing, isTrue);
      expect(s.speed, 1.5);
      expect(s.processingState, AudioProcessingState.ready);
    });

    test('the control offered is the opposite of what is happening', () {
      expect(
        mediaPlaybackState(
          phase: MediaPhase.playing,
          positionSeconds: 0,
          now: _futurama,
        ).controls,
        [MediaControl.pause],
      );
      expect(
        mediaPlaybackState(
          phase: MediaPhase.paused,
          positionSeconds: 0,
          now: _futurama,
        ).controls,
        [MediaControl.play],
      );
    });

    test('position is clamped to the catalog runtime', () {
      // A transcode's relative clock can overshoot `catalogDuration` at the tail.
      final over = mediaPlaybackState(
        phase: MediaPhase.playing,
        positionSeconds: 1400,
        now: _futurama,
      );
      expect(over.updatePosition, const Duration(seconds: 1320));

      final under = mediaPlaybackState(
        phase: MediaPhase.playing,
        positionSeconds: -5,
        now: _futurama,
      );
      expect(under.updatePosition, Duration.zero);
    });

    test('finishing pins the scrubber to the end', () {
      final s = mediaPlaybackState(
        phase: MediaPhase.finished,
        positionSeconds: 1301,
        now: _futurama,
      );
      expect(s.updatePosition, const Duration(seconds: 1320));
      expect(s.processingState, AudioProcessingState.completed);
    });

    test('a position with no known runtime passes through unclamped', () {
      final s = mediaPlaybackState(
        phase: MediaPhase.playing,
        positionSeconds: 99,
        now: _unknownRuntime,
      );
      expect(s.updatePosition, const Duration(seconds: 99));
    });
  });

  group('session ownership', () {
    // Series auto-advance does a pushReplacement, and the outgoing route's
    // dispose lands ~300ms *after* the incoming route has attached. Without
    // identity arbitration the finished episode tears down its successor's
    // session on the way out.
    test('a stale detach leaves the incoming controller in charge', () {
      final handler = ArgosyAudioHandler();
      final outgoing = _FakeTarget();
      final incoming = _FakeTarget();

      handler.attach(outgoing, _futurama);
      handler.attach(incoming, _futurama);
      handler.detach(outgoing);

      expect(handler.isCurrent(incoming), isTrue);
      expect(handler.mediaItem.value, isNotNull);

      handler.play();
      expect(incoming.played, 1);
      expect(outgoing.played, 0);
    });

    test('a stale push cannot move the incoming episode scrubber', () {
      final handler = ArgosyAudioHandler();
      final outgoing = _FakeTarget();
      final incoming = _FakeTarget();

      handler.attach(outgoing, _futurama);
      handler.attach(incoming, _futurama);
      handler.push(
        incoming,
        mediaPlaybackState(
          phase: MediaPhase.playing,
          positionSeconds: 30,
          now: _futurama,
        ),
      );
      handler.push(
        outgoing,
        mediaPlaybackState(
          phase: MediaPhase.finished,
          positionSeconds: 1320,
          now: _futurama,
        ),
      );

      expect(handler.playbackState.value.updatePosition,
          const Duration(seconds: 30));
    });

    test('the owning controller detaching clears the session', () {
      final handler = ArgosyAudioHandler();
      final target = _FakeTarget();

      handler.attach(target, _futurama);
      handler.detach(target);

      expect(handler.isCurrent(target), isFalse);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.playing, isFalse);

      // Commands after teardown are dropped, not routed at a dead controller.
      handler.play();
      expect(target.played, 0);
    });

    test('the notification stop action pauses rather than tearing down', () {
      // The player screen may still be mounted behind the lock screen; only the
      // controller's own dispose ends the session.
      final handler = ArgosyAudioHandler();
      final target = _FakeTarget();

      handler.attach(target, _futurama);
      handler.stop();

      expect(target.paused, 1);
      expect(handler.isCurrent(target), isTrue);
    });

    test('a lock-screen seek arrives as absolute seconds', () {
      final handler = ArgosyAudioHandler();
      final target = _FakeTarget();

      handler.attach(target, _futurama);
      handler.seek(const Duration(minutes: 3, seconds: 20));

      expect(target.seeks, [200.0]);
    });
  });
}

class _FakeTarget implements MediaSessionTarget {
  int played = 0;
  int paused = 0;
  final List<double> seeks = [];

  @override
  Future<void> play() async => played++;

  @override
  Future<void> pause() async => paused++;

  @override
  Future<void> seekTo(double seconds) async => seeks.add(seconds);
}
