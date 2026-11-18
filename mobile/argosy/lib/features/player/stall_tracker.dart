/// Why the player stalled, as best the client can tell (ARGY-313).
enum StallCause {
  /// Within [StallTracker.causeWindow] of a user seek.
  seek,

  /// Within [StallTracker.causeWindow] of the app returning to the foreground
  /// or leaving PiP.
  resume,

  /// Mid-playback, nothing nearby to blame.
  play,
}

/// One finished (or abandoned) rebuffer.
class StallReport {
  const StallReport({
    required this.positionSeconds,
    required this.duration,
    required this.cause,
    required this.ended,
    this.recovered = false,
    this.bufferedAheadSeconds,
  });

  /// Playhead when the stall began, in the player's own timeline. The
  /// controller turns it into absolute media time before sending.
  final double positionSeconds;
  final Duration duration;
  final StallCause cause;

  /// False when the viewer left the player mid-stall; [duration] is then the
  /// time so far.
  final bool ended;

  /// True when the stall ended because the controller's recovery restarted the
  /// session after the stream died. [ended] is false then too.
  final bool recovered;
  final double? bufferedAheadSeconds;
}

/// Times each rebuffer from `bufferingStart` to `bufferingEnd` and decides
/// whether it is worth reporting.
///
/// The server cannot tell a stall from a pause (the progress heartbeat fires on
/// a timer either way), so the player says so. What it must NOT say is that the
/// start-up buffer, or the buffer behind the player's own source swap or
/// transcode restart, was a stall: the viewer asked for those and they already
/// have their own `starting` phase. The tracker is therefore *disarmed* until
/// the controller sees real playback, and disarmed again whenever it begins a
/// (re)start.
///
/// Pure Dart with an injected clock, so the state machine is testable without
/// a native player.
class StallTracker {
  StallTracker({
    required this.onReport,
    DateTime Function()? now,
    this.minStall = const Duration(milliseconds: 250),
    this.minInterval = const Duration(seconds: 2),
    this.causeWindow = const Duration(seconds: 5),
  }) : _now = now ?? DateTime.now;

  /// Receives each report that survives suppression and the throttle. Called
  /// synchronously; it must not throw into playback.
  final void Function(StallReport report) onReport;
  final DateTime Function() _now;

  /// Stalls shorter than this are the decoder catching its breath, not a
  /// buffer the viewer sat through.
  final Duration minStall;

  /// At most one report per this interval, so a flapping link cannot turn into
  /// a request storm. Stalls inside it are dropped, not queued.
  final Duration minInterval;

  /// How long after a seek / resume a stall is blamed on it.
  final Duration causeWindow;

  bool _armed = false;
  DateTime? _stallStart;
  double _stallPosition = 0;
  double? _stallAhead;
  StallCause _stallCause = StallCause.play;
  DateTime? _lastSeek;
  DateTime? _lastResume;
  DateTime? _lastReport;

  bool get armed => _armed;

  /// Whether a stall is currently open.
  bool get inStall => _stallStart != null;

  /// Real playback has begun: buffering from here on is a stall. Idempotent.
  void arm() => _armed = true;

  /// A start-up, source swap or transcode restart began. Whatever it buffers is
  /// expected, and a stall open across it belongs to the old source: dropped,
  /// not reported.
  void disarm() {
    _armed = false;
    _stallStart = null;
  }

  /// The viewer sought.
  void noteSeek() => _lastSeek = _now();

  /// The app came back to the foreground, or left PiP.
  void noteResume() => _lastResume = _now();

  /// The player began buffering at [positionSeconds].
  void bufferingStart({
    required double positionSeconds,
    double? bufferedAheadSeconds,
  }) {
    if (!_armed || _stallStart != null) return;
    final now = _now();
    _stallStart = now;
    _stallPosition = positionSeconds;
    _stallAhead = bufferedAheadSeconds;
    _stallCause = _within(_lastSeek, now)
        ? StallCause.seek
        : _within(_lastResume, now)
        ? StallCause.resume
        : StallCause.play;
  }

  /// The player stopped buffering.
  void bufferingEnd() => _finish(ended: true);

  /// The viewer left the player. A stall still open is reported with the time
  /// so far and `ended: false`.
  void abandon() {
    _finish(ended: false);
    _armed = false;
  }

  /// The stream died mid-stall and recovery is about to restart the session.
  /// A stall still open is reported with the time so far, `ended: false` and
  /// `recovered: true`: it is the longest stall there is, and the restart that
  /// follows would otherwise disarm it away. Without an open stall nothing is
  /// reported (an error while playing is not a stall).
  void recover() => _finish(ended: false, recovered: true);

  bool _within(DateTime? at, DateTime now) =>
      at != null && now.difference(at) <= causeWindow;

  void _finish({required bool ended, bool recovered = false}) {
    final start = _stallStart;
    if (start == null) return;
    _stallStart = null;
    final now = _now();
    final took = now.difference(start);
    if (took < minStall) return;
    final last = _lastReport;
    if (last != null && now.difference(last) < minInterval) return;
    _lastReport = now;
    onReport(
      StallReport(
        positionSeconds: _stallPosition,
        duration: took,
        cause: _stallCause,
        ended: ended,
        recovered: recovered,
        bufferedAheadSeconds: _stallAhead,
      ),
    );
  }
}
