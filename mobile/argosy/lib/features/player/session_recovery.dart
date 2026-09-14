/// Surviving a transcode session that vanishes under the player (ARGY-239).
///
/// The server reaps a session nothing has touched for its idle TTL (5 min in
/// prod). A reaped session's segments 404, and the player only finds out once it
/// has played through what it already buffered, which can be minutes after the
/// session actually died. The web player learned both halves of this in ARGY-107;
/// the mobile and TV player shipped before that and never got either. These are
/// its pieces, kept free of the plugin so the rules can be tested directly.
library;

/// What to do with a fatal player error on a transcode session.
enum RecoveryDecision {
  /// Restart the transcode at the current position.
  restart,

  /// A restart is already in flight; this is the same failure arriving again.
  duplicate,

  /// The retry budget is spent without playback ever advancing. Surface it.
  giveUp,
}

/// The retry budget for restarting a dead transcode session, mirroring the web
/// player's `recovering` / `recoveryAttempts` / `recoveryFrom`.
///
/// Two separate questions, kept apart on purpose:
/// - [inFlight] is "a restart is already running". better_player_plus posts
///   `exception` on *every* value change while the error stands, so one
///   failure arrives many times, and all but the first are duplicates to drop.
/// - [attempts] is "how many restarts has this stream had without playing". It
///   alone decides when to stop, because it is the one thing cleared only by real
///   forward progress.
///
/// Forward progress means the absolute position passing the point the restart
/// began from. The web player tried two cheaper signals and both fired on a
/// restart that was about to fail. `play` fires when playback is *requested*
/// (ARGY-220); a buffered fragment arrives even when the decoder then rejects it
/// (ARGY-223). Either one re-armed the guard and let the loop run unbounded.
class SessionRecovery {
  /// Two, not one: a reap legitimately needs one retry, and a second covers a
  /// reap landing during the first. Past that the failure isn't transient.
  static const maxAttempts = 2;

  /// Forward progress worth believing: long enough not to trip while the
  /// player settles at the restart position, short enough that a stream really
  /// playing clears it within a second.
  static const progressSeconds = 0.5;

  bool _inFlight = false;
  int _attempts = 0;
  double _from = 0;

  bool get inFlight => _inFlight;
  int get attempts => _attempts;

  /// Gives a deliberately started stream a clean budget: the first play, a seek
  /// that restarts the session, or the overlay's retry. Never called from the
  /// recovery path itself, which would defeat the cap.
  void reset(double from) {
    _inFlight = false;
    _attempts = 0;
    _from = from;
  }

  /// A fatal error arrived with the playhead at [position] (absolute seconds).
  RecoveryDecision onFatal(double position) {
    if (_inFlight) return RecoveryDecision.duplicate;
    if (_attempts >= maxAttempts) return RecoveryDecision.giveUp;
    _inFlight = true;
    _attempts++;
    _from = position;
    return RecoveryDecision.restart;
  }

  /// The restart finished, however it went. Whether the new session is any good
  /// is not this flag's question. Holding it until playback advances would make
  /// the next failure look like a duplicate, and the attempt it was owed would
  /// silently never run (ARGY-223 review).
  void settled() => _inFlight = false;

  /// The playhead reached [position] (absolute seconds). Past where the last
  /// restart began, that proves the session decodes and re-arms recovery for a
  /// future reap.
  void progressed(double position) {
    if (_attempts > 0 && position > _from + progressSeconds) {
      _inFlight = false;
      _attempts = 0;
    }
  }
}

/// How long a paused player keeps its transcode session alive.
///
/// Long enough for the pauses people actually take (a call, dinner), so resuming
/// plays straight on. Short enough that a player left paused in a pocket, or on
/// a TV nobody is watching, doesn't hold a session slot indefinitely. Past it
/// the reaper collects the session and [SessionRecovery] restarts it on resume,
/// at the cost of a brief spinner.
const pausedKeepaliveLimit = Duration(minutes: 30);

/// Whether the heartbeat should touch the session while the player is not
/// playing (ARGY-239, web's ARGY-107 keepalive).
///
/// The progress report is what touches the session server-side (`TouchItem`),
/// and the heartbeat used to send it only while playing. A pause therefore
/// stopped every touch, and the reaper took the session five minutes in.
///
/// [hasSession] is false for direct play and stowed files, which have no
/// session to keep, and false once the controller is torn down: ARGY-190's
/// detached path depends on the reaper collecting a dead host's session.
bool keepsPausedSessionAlive({
  required bool hasSession,
  required DateTime? pausedSince,
  required DateTime now,
}) =>
    hasSession &&
    pausedSince != null &&
    now.difference(pausedSince) < pausedKeepaliveLimit;
