import 'package:argosy/features/player/session_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mobile/TV side of ARGY-107 (ARGY-239). The web player's guard had to be
/// rebuilt twice (ARGY-220, ARGY-223) because it re-armed on a signal that
/// fires even when the restart is about to fail. These pin down the rules that
/// came out of that: the cap latches, duplicates don't spend it, and only real
/// forward progress restores it.
void main() {
  group('SessionRecovery', () {
    test('a reap restarts from where the playhead is', () {
      final r = SessionRecovery()..reset(0);

      expect(r.onFatal(612), RecoveryDecision.restart);
      expect(r.inFlight, isTrue);
      expect(r.attempts, 1);
    });

    test('the same failure arriving again mid-restart is a duplicate', () {
      // better_player_plus re-posts `exception` on every value change while the
      // error stands, so one dead session reports itself many times.
      final r = SessionRecovery()..reset(0);
      r.onFatal(612);

      expect(r.onFatal(612), RecoveryDecision.duplicate);
      expect(r.onFatal(612), RecoveryDecision.duplicate);
      expect(r.attempts, 1);
    });

    test('the cap latches when restarts never play', () {
      final r = SessionRecovery()..reset(0);

      expect(r.onFatal(612), RecoveryDecision.restart);
      r.settled();
      expect(r.onFatal(612), RecoveryDecision.restart);
      r.settled();
      expect(r.onFatal(612), RecoveryDecision.giveUp);
      expect(r.onFatal(612), RecoveryDecision.giveUp);
    });

    test('settling does not re-arm; only progress does', () {
      // ARGY-220: re-arming on "playback was requested" let a stream that could
      // never decode loop forever. A settled restart is no proof of anything.
      final r = SessionRecovery()..reset(0);
      r
        ..onFatal(612)
        ..settled()
        ..onFatal(612)
        ..settled();

      // The playhead sitting at the restart point, or jittering just past it,
      // is not progress.
      r.progressed(612);
      r.progressed(612.4);
      expect(r.onFatal(612), RecoveryDecision.giveUp);
    });

    test('playing past the restart point re-arms for a later reap', () {
      final r = SessionRecovery()..reset(0);
      r
        ..onFatal(612)
        ..settled()
        ..onFatal(612)
        ..settled();

      r.progressed(613);

      expect(r.attempts, 0);
      // Another pause, another reap, much later: owed its full budget.
      expect(r.onFatal(2400), RecoveryDecision.restart);
      r.settled();
      expect(r.onFatal(2400), RecoveryDecision.restart);
    });

    test('progress is measured from the latest restart, not the first', () {
      final r = SessionRecovery()..reset(0);
      r
        ..onFatal(100)
        ..settled()
        ..onFatal(900)
        ..settled();

      // Well past the first restart, still short of the second.
      r.progressed(500);

      expect(r.attempts, 2);
    });

    test('a viewer-driven start gets a fresh budget', () {
      final r = SessionRecovery()..reset(0);
      r
        ..onFatal(612)
        ..settled()
        ..onFatal(612)
        ..settled();

      r.reset(1200); // a seek that restarts the session, or Retry

      expect(r.onFatal(1200), RecoveryDecision.restart);
    });
  });

  group('keepsPausedSessionAlive', () {
    final now = DateTime(2026, 9, 14, 14, 52);

    test('a paused transcode keeps touching its session', () {
      expect(
        keepsPausedSessionAlive(
          hasSession: true,
          // The ARGY-239 report: ten minutes paused, reaped at five.
          pausedSince: now.subtract(const Duration(minutes: 10)),
          now: now,
        ),
        isTrue,
      );
    });

    test('nothing to keep without a session', () {
      // Direct play, a stowed file, or a controller already torn down, which
      // ARGY-190 needs the reaper to be free to collect.
      expect(
        keepsPausedSessionAlive(
          hasSession: false,
          pausedSince: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('not paused means the playing heartbeat has it', () {
      expect(
        keepsPausedSessionAlive(hasSession: true, pausedSince: null, now: now),
        isFalse,
      );
    });

    test('an abandoned pause lets the reaper have the session', () {
      expect(
        keepsPausedSessionAlive(
          hasSession: true,
          pausedSince: now.subtract(pausedKeepaliveLimit),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
