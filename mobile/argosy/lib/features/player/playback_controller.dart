import 'dart:async';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../api/client_identity.dart';
import '../../api/device_preferences_copy.dart';
import '../stow/offline_progress_queue.dart';
import 'argosy_audio_handler.dart';
import 'media_session_state.dart';
import 'session_recovery.dart';
import 'vtt.dart';

enum _NextFetch { unfetched, fetched, failed }

/// Orchestrates a single playback session, mirroring the shipped web player
/// (`web/src/views/PlayerView.vue`). It owns the [BetterPlayerController] and the
/// transcode-session lifecycle, and exposes a small surface for the Argosy
/// controls overlay (which replaces better_player_plus's built-in UI).
///
/// Key invariants (ARGY-79):
/// - **Duration** comes from the catalog ([catalogDuration]), never the HLS
///   playlist — an `event` playlist only knows the encoded-so-far length.
/// - Absolute media position is `baseOffset + player.position`, where
///   [baseOffset] is the transcode StartAt (always 0 for direct play).
/// - **Seeking** under transcode is native when the target is already encoded;
///   otherwise the session is torn down and restarted at the new offset, so
///   ffmpeg re-seeks server-side. Resume takes the same restart path.
class PlaybackController extends ChangeNotifier
    with WidgetsBindingObserver
    implements MediaSessionTarget {
  PlaybackController({
    required this.libraryApi,
    required this.transcodeApi,
    required this.authApi,
    required this.baseUrl,
    required this.token,
    required this.itemId,
    required this.title,
    required this.catalogDuration,
    required this.isTranscode,
    required this.hevc,
    required this.hevcHardware,
    this.minHeight,
    this.maxHeight,
    required this.subtitles,
    required this.preferredLanguages,
    required this.prefs,
    this.notificationAuthor,
    this.artworkUrl,
    this.localPath,
    this.localSubtitles = const [],
    this.offlineQueue,
  }) {
    // ARGY-190: the host activity can be destroyed without this controller ever
    // being disposed — see [didChangeAppLifecycleState].
    WidgetsBinding.instance.addObserver(this);
  }

  final LibraryApi libraryApi;
  final TranscodeApi transcodeApi;
  final AuthApi authApi;
  final String baseUrl;
  final String? token;
  final String itemId;

  /// Title shown in the lock-screen / notification media controls (ARGY-50).
  final String title;

  /// Secondary line for the media notification (e.g. the year); optional.
  final String? notificationAuthor;

  /// Absolute artwork URL for the media notification; optional. The server
  /// serves artwork unauthenticated, so no token is appended.
  final String? artworkUrl;

  /// Total runtime from the catalog, in seconds (the scrub bar's domain).
  final double catalogDuration;

  /// Whether playback goes through an HLS transcode session vs. a direct stream.
  final bool isTranscode;

  /// Absolute path to a stowed copy of this item (ARGY-49). When set, playback
  /// reads from disk and the network is never touched — the case the whole
  /// feature exists for.
  final String? localPath;

  /// WebVTT sidecars stowed alongside [localPath], keyed by the same track id
  /// the picker and the saved caption preference use.
  final List<({String id, String label, String language, String path})>
  localSubtitles;

  /// Where resume positions go when the server can't be reached. Without it an
  /// episode watched offline still reads as unstarted once you land.
  final OfflineProgressQueue? offlineQueue;

  /// Whether this session is playing a stowed file.
  bool get isOffline => localPath != null && localPath!.isNotEmpty;

  /// Whether the device advertised 4K-HEVC decode to the transcoder.
  final bool hevc;

  /// Whether the device advertised a hardware HEVC Main10 4K decoder (ARGY-179
  /// ruling 2), which lets the server copy 10-bit 4K HEVC rather than re-encode.
  final bool hevcHardware;

  /// Ladder hints (ARGY-179): the lowest and highest rung heights the client
  /// wants; null means not sent, and the server shapes the full ladder. The TV
  /// sends both equal to its display-mode height, the phone sends neither.
  /// Final so every restart — seek, recovery, next episode — negotiates the
  /// same output and the same session key.
  final int? minHeight;
  final int? maxHeight;

  /// Subtitle tracks available for the item (populated up front).
  final List<SubtitleTrack> subtitles;

  /// Household preferred audio/subtitle languages (ARGY-154); the track sheet
  /// shows matching tracks by default and folds the rest behind "More options".
  final List<String> preferredLanguages;

  DevicePreferences? prefs;

  /// Series auto-advance (ARGY-93, mirrors web ARGY-89): the episode to roll into
  /// when this one finishes, loaded lazily once playback starts (only when
  /// [autoAdvance] is on). Null for films or the last episode of a series.
  OnDeckItem? nextEpisode;

  /// Set when the viewer dismisses the Up Next card: suppresses the card and the
  /// end-of-file roll-over for the rest of this episode.
  bool upNextCancelled = false;

  /// Invoked when playback should roll into [nextEpisode] — on end-of-file or
  /// "Play now". The screen owns navigation, so it wires this up.
  VoidCallback? onAdvance;

  /// Invoked when the host activity was destroyed under a live player
  /// (ARGY-190). The session is already torn down by then; this exists purely so
  /// the screen can leave the player route, because the widget tree survives the
  /// activity and would otherwise come back to a player with no native side.
  VoidCallback? onHostDetached;

  bool _advancing = false;

  /// Whether series auto-advance is enabled for this device (default on).
  bool get autoAdvance => prefs?.seriesAutoAdvance ?? true;

  /// Seconds before the end at which the Up Next / Play Next card surfaces.
  static const upNextLeadSeconds = 40;

  /// How long the card counts down once it opens — a real timer, not a function
  /// of the playhead (ARGY-207). Deriving it from remaining time only looked
  /// right on a straight playthrough, where the card happens to open exactly this
  /// far ahead of the roll-over: seeking into the window handed out whatever was
  /// left, down to an instant, unexplained jump for anything past it. Playing
  /// straight through is unchanged — the card still opens 40s out and rolls with
  /// ~25s of file left. Manual Play Next jumps immediately.
  static const upNextCountdownSeconds = 15;

  /// Seconds the viewer must have played, forward and uninterrupted since the
  /// last seek, before a seek-reached Up Next card starts counting down
  /// (ARGY-261). Hunting for a scene in the last minutes must not roll the
  /// episode; the card still opens so Play Next stays one tap away.
  static const upNextArmSeconds = 5;

  /// Playback seconds accrued from `progress` events since the last seek. Infinite
  /// until the first seek: reaching the window by playing is never held. Counted
  /// from the playhead, not the wall clock, so a paused player accrues nothing.
  double _playedSinceSeek = double.infinity;
  double? _lastProgressPos;

  /// True while the card is up but its countdown is held back by a seek.
  ///
  /// Never held once the media has really ended: nothing is left to watch, so the
  /// card counts down as ARGY-207 intended and Cancel is the way out.
  bool get upNextHeld => !_playedPastSeek && !_finished;

  /// Whether the viewer has actually watched into where they are, which is what
  /// decides if `finished` is the media ending or the echo of a seek.
  bool get _playedPastSeek => _playedSinceSeek >= upNextArmSeconds;

  void _noteSeek() {
    _playedSinceSeek = 0;
    _lastProgressPos = null;
  }

  void _accruePlayed() {
    final pos = position;
    final last = _lastProgressPos;
    _lastProgressPos = pos;
    if (last == null) return;
    final d = pos - last;
    // Forward and small: a bigger jump is a seek or a restart, not playing.
    if (d <= 0 || d > 3) return;
    final wasHeld = !_playedPastSeek;
    _playedSinceSeek += d;
    if (wasHeld && _playedPastSeek && upNextOpen) {
      _upNextLeftMs = upNextCountdownSeconds * 1000;
      _upNextLastTick = debugNow();
      _safeNotify();
    }
  }

  /// Whether the Up Next card should be showing, and the seconds left on its
  /// countdown. Both players render from these rather than deriving them, so the
  /// countdown has one owner and one timer.
  bool upNextOpen = false;
  int upNextCountdown = upNextCountdownSeconds;

  Timer? _upNextTimer;

  /// Test seams for the countdown: a manual clock, a stand-in for the player's
  /// playing state, and a way to run one tick without waiting on the timer.
  @visibleForTesting
  DateTime Function() debugNow = DateTime.now;
  @visibleForTesting
  bool? debugPlaying;
  @visibleForTesting
  void debugTickUpNext() => _tickUpNext();
  int _upNextLeftMs = 0;
  DateTime? _upNextLastTick;

  /// Aggressive buffering for smoother playback on remote/flaky links, mirroring
  /// the web player's deep hls.js buffer. A remux is a single video rendition with
  /// nothing to fall back to, and even a laddered transcode is cheaper to ride out
  /// than to downshift, so a deep buffer is our first defense against a bandwidth
  /// dip. The server transcodes far ahead of the playhead and won't reap a live
  /// session with a full buffer, so it can feed this. Levers exposed by
  /// better_player_plus map to ExoPlayer's DefaultLoadControl:
  /// - minBufferMs 50s (from 25s): maintain a deeper continuous floor.
  /// - maxBufferMs 10min: the time ceiling. ExoPlayer *also* caps by an internal
  ///   per-track byte target that the plugin doesn't expose, so the real ahead-depth
  ///   is bounded there (≈ its default video buffer size) — this can't be raised from
  ///   Dart without forking the plugin (tracked as a follow-up).
  /// - bufferForPlaybackAfterRebufferMs 10s (from 6s): rebuild a bigger cushion
  ///   after a stall so a shaky remote link doesn't repeatedly micro-stall.
  static const _bufferingConfig = BetterPlayerBufferingConfiguration(
    minBufferMs: 50000,
    maxBufferMs: 600000,
    bufferForPlaybackAfterRebufferMs: 10000,
  );

  BetterPlayerController? _player;
  BetterPlayerController? get player => _player;

  /// The latest frame of video state (position, buffering, playing…) for the
  /// overlay. Null until the first data source is set up.
  VideoPlayerValue? get videoValue =>
      debugVideoValue ?? _player?.videoPlayerController?.value;

  /// Test seam: stands in for the plugin's value, so a test can hand the
  /// controller a relative position the way a live player would.
  @visibleForTesting
  VideoPlayerValue? debugVideoValue;

  /// True once the player has a data source whose first frame is ready to
  /// render. Deliberately avoids better_player's `isVideoInitialized()`, which
  /// *throws* StateError while the data source is still being set up — the
  /// source of a transient red error frame during the loading spinner.
  bool get isReady => videoValue?.initialized ?? false;

  String? _sessionId;

  /// The transcode StartAt for the current session (0 for direct play). Added
  /// to the player's relative position to get absolute media time.
  double baseOffset = 0;

  /// How much of the current transcode session ffmpeg had written when the
  /// player initialised — the plugin's own duration reading at that moment,
  /// captured before [pinSessionDuration] overwrites it. The floor for
  /// [_encodedSoFarSeconds]; buffered ranges raise it from there.
  double _windowAtInitSeconds = 0;

  /// Restart generation (ARGY-260). Every [_startTranscodeAt] takes the next
  /// number and, after each await, bails silently if a newer restart has taken
  /// it: the newest seek always wins, and a superseded one is not a failure.
  int _restartGen = 0;

  /// The generation whose source is allowed to commit [_pendingOffset] when the
  /// plugin reports `initialized`.
  int _attachGen = -1;

  /// Where the restart in flight is headed. [baseOffset] is only moved here when
  /// the new source is actually up, so the old source's position is never added
  /// to the new offset (the scrub-bar flash). Non-null means a restart is in
  /// flight; [position] answers with it meanwhile.
  double? _pendingOffset;

  /// The stop of the previous session, which any restart awaits before POSTing
  /// (ARGY-220) — including a restart that found no session id to stop because
  /// the one before it already took it.
  Future<void>? _pendingStop;

  /// Session ids a restart has taken over to stop.
  final _stopping = <String>{};

  /// A `finished` within this many seconds of the catalog end is the media
  /// really ending, whatever seek preceded it.
  static const _realEndSlackSeconds = 1.0;

  /// A seek was just issued, so a `finished` right behind it is the plugin
  /// clamping the target, not the media ending. Cleared by the next `progress`.
  bool _seekJustIssued = false;

  /// Test seams: no native player sits behind the controller in unit tests.
  @visibleForTesting
  Future<bool> Function(String url, bool Function() cancelled)? debugProbe;
  @visibleForTesting
  Future<void> Function(String playlistUrl)? debugAttach;

  /// True while a session is (re)starting — the overlay shows a spinner.
  bool starting = false;

  /// Set when playback hits an unrecoverable error; the overlay offers a retry.
  bool fatalError = false;
  String? errorMessage;

  String? _activeSubtitleId;
  String? get activeSubtitleId => _activeSubtitleId;

  Timer? _heartbeat;

  /// When the heartbeat first saw playback stopped, or null while playing.
  /// Measured by the heartbeat rather than the `pause` event on purpose: a pause
  /// the platform makes (audio focus lost to a call, headphones pulled) changes
  /// the player's value without posting that event, and a call is exactly the
  /// long pause the keepalive exists for (ARGY-239).
  DateTime? _pausedSince;

  /// The retry budget for restarting a session that died under the player.
  final _recovery = SessionRecovery();

  bool _disposed = false;
  bool _tornDown = false;

  Map<String, String> get _authHeaders => {
        ...ClientIdentity.header,
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// better_player_plus's own now-playing integration — **off on Android, kept
  /// on iOS** (ARGY-87).
  ///
  /// On Android the flag posted two separate notifications (the plugin's media3
  /// `PlayerNotificationManager` *and* its foreground service's "Playing in
  /// background") and attached a MediaSession token to neither, so System UI
  /// treated them as ordinary notifications: no lock-screen transport controls,
  /// and Do Not Disturb swallowed them. [ArgosyAudioHandler] owns a real session
  /// there instead.
  ///
  /// On iOS the *same* flag drives a path that works: it activates the
  /// AVAudioSession, begins receiving remote-control events, and populates
  /// `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`. This is an Android bug,
  /// so iOS is deliberately left exactly as it was.
  BetterPlayerNotificationConfiguration get _notificationConfig =>
      BetterPlayerNotificationConfiguration(
        showNotification: !Platform.isAndroid,
        title: title,
        author: notificationAuthor,
        imageUrl: artworkUrl,
        activityName: 'MainActivity',
      );

  /// Metadata for the media notification / lock screen.
  NowPlaying get _nowPlaying => NowPlaying(
    id: itemId,
    title: title,
    subtitle: notificationAuthor,
    artworkUrl: artworkUrl,
    durationSeconds: catalogDuration,
  );

  /// Where the transport currently is, in the session's terms. Order matters:
  /// a stalled player must not report itself as playing, or the lock-screen
  /// scrubber runs ahead of the video.
  MediaPhase get _phase {
    if (starting) return MediaPhase.starting;
    final v = videoValue;
    if (v == null) return MediaPhase.starting;
    if (_finished) return MediaPhase.finished;
    if (v.isBuffering) return MediaPhase.buffering;
    return v.isPlaying ? MediaPhase.playing : MediaPhase.paused;
  }

  /// Publishes the current transport state to the media session. Cheap and
  /// idempotent — the handler drops it if this controller has been superseded.
  ///
  /// Called on transport events and on the existing 10s heartbeat rather than
  /// per frame: [PlaybackState] carries an update timestamp and System UI
  /// extrapolates the position between pushes.
  void _pushSession({MediaPhase? phase, double? position}) {
    final h = argosyAudioHandler;
    if (h == null) return;
    h.push(
      this,
      mediaPlaybackState(
        phase: phase ?? _phase,
        positionSeconds: position ?? this.position,
        now: _nowPlaying,
        bufferedSeconds: baseOffset + _encodedSoFarSeconds(),
        speed: videoValue?.speed ?? 1.0,
      ),
    );
  }

  bool _finished = false;

  @visibleForTesting
  bool get debugFinished => _finished;

  /// Friendly quality stamp derived from the decoded video height, mirroring
  /// the web player's `updateQuality`: "4K" at ≥2160p, otherwise `{height}p`.
  /// Null until the first frame reports a size.
  String? get qualityLabel {
    final h = videoValue?.size?.height;
    if (h == null || h <= 0) return null;
    final hi = h.round();
    return hi >= 2160 ? '4K' : '${hi}p';
  }

  /// Absolute media position in seconds (`baseOffset + player.position`).
  double get position {
    final pending = _pendingOffset;
    if (pending != null) return pending;
    final ms = videoValue?.position.inMilliseconds ?? 0;
    return baseOffset + ms / 1000.0;
  }

  /// The last absolute position known to be real (ARGY-283): a deliberate
  /// start or seek, or a `progress` reading inside the catalog's bounds. Any
  /// restart whose derived position is not believable begins here instead.
  double _lastGoodPosition = 0;

  @visibleForTesting
  double get debugLastGoodPosition => _lastGoodPosition;

  /// How far past the catalog end a position may read and still be believed:
  /// a file can outrun its catalogued runtime by a few seconds, and a player
  /// draining its last buffer reports a hair past the end. The server refuses
  /// progress beyond the same margin (`progressSlackSeconds`), so what passes
  /// here is what it will accept.
  static const positionSlackSeconds = 10.0;

  /// Whether [p] can be a position in this title: finite, not negative, and no
  /// further past the catalog end than [positionSlackSeconds]. Anything else
  /// is the arithmetic of a broken player, not a place in the episode.
  bool isSanePosition(double p) =>
      p.isFinite &&
      p >= 0 &&
      (catalogDuration <= 0 || p <= catalogDuration + positionSlackSeconds);

  /// Where playback should (re)start: [candidate] — the playhead by default —
  /// when it is believable, else the last good position; always finite and
  /// within [0, catalogDuration]. The one place a start offset is derived, so
  /// nothing outside the title can reach a transcode start or a progress
  /// report (ARGY-283: a wedged recovery POSTed startAt=44842 into a 1355s
  /// episode, ten times).
  double _resumePoint([double? candidate]) {
    final p = candidate ?? position;
    final base = isSanePosition(p) ? p : _lastGoodPosition;
    if (!base.isFinite || base < 0) return 0;
    if (catalogDuration > 0 && base > catalogDuration) return catalogDuration;
    return base;
  }

  // --- lifecycle -----------------------------------------------------------

  /// Begins playback at [offset] seconds of absolute media time. For transcode
  /// this starts ffmpeg at that offset; for direct play it seeks the element.
  Future<void> start(double offset) async {
    // The saved position is the first thing believed about where we are, so it
    // is checked like any other: a server-side value past the end starts over.
    offset = _resumePoint(offset);
    _lastGoodPosition = offset;
    // A deliberate start is a fresh subject, so it gets a fresh retry budget.
    _recovery.reset(offset);
    _player = BetterPlayerController(
      BetterPlayerConfiguration(
        fit: BoxFit.contain,
        autoDispose: false,
        // The Argosy overlay supplies all transport UI; hide the built-in one.
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          showControls: false,
        ),
        subtitlesConfiguration: _captionConfig(prefs),
        // Keep playing when the app backgrounds — the whole point of the media
        // session (ARGY-87). Until now this fell out of a side effect: the
        // plugin's `_isAutomaticPlayPauseHandled()` is
        // `!showNotification && handleLifecycle`, so setting `showNotification`
        // for its (broken) Android notification also suppressed auto-pause. With
        // that flag now off on Android, this has to be said out loud. No-op on
        // iOS, where `showNotification` still covers it.
        handleLifecycle: false,
      ),
    )..addEventsListener(_onEvent);

    // Claim the media session before the transcode handshake: `_waitForPlaylist`
    // polls for up to 20s, and the foreground service behind the session is what
    // keeps that (and the stream after it) alive if the screen goes off.
    argosyAudioHandler?.attach(this, _nowPlaying);
    _pushSession(phase: MediaPhase.starting, position: offset);

    if (isOffline) {
      await _startLocal(offset);
    } else if (isTranscode) {
      await _startTranscodeAt(offset);
    } else {
      await _startDirect(offset);
    }
    _startHeartbeat();
    _applyPreferredSubtitle();
    // Auto-advance needs the server to know what comes next; offline it simply
    // doesn't apply, and asking would block on a socket that isn't there.
    unawaited(_loadNextEpisode());
  }

  /// Where the next-episode lookup stands (ARGY-264). A failed request used to
  /// read as "last episode", so one blip at start disabled Up Next for the whole
  /// episode. Only a server answer (an episode, or 404) is terminal.
  _NextFetch _nextFetch = _NextFetch.unfetched;
  int _nextAttempts = 0;
  DateTime? _nextLastAttempt;
  Future<void>? _nextInFlight;
  bool _nextFinalTried = false;

  /// Most lookups per episode, and the least gap between them. The three retry
  /// triggers (restart, window entry, end of file) all fire on a link that may
  /// still be dead, so these are what keep a bad link from becoming a storm.
  static const int nextEpisodeMaxAttempts = 3;
  static const Duration nextEpisodeRetryGap = Duration(seconds: 10);

  @visibleForTesting
  int get debugNextAttempts => _nextAttempts;

  /// The lookup `start()` kicks off, which tests can't reach (it builds the
  /// native player).
  @visibleForTesting
  Future<void> debugLoadNextEpisode() => _loadNextEpisode();

  bool get _nextFetchFailed => _nextFetch == _NextFetch.failed;

  /// Fetches the next episode for auto-advance. A 404 (last episode, or not a
  /// series episode) is an answer: [nextEpisode] stays null and is never asked
  /// again. Any other error leaves the lookup retryable. [last] is the
  /// end-of-file attempt, which skips the spacing and the cap once, because
  /// the alternative is stranding the viewer on a black frame.
  Future<void> _loadNextEpisode({bool last = false}) {
    if (isOffline || !autoAdvance || _disposed || _tornDown) {
      return Future.value();
    }
    if (_nextFetch == _NextFetch.fetched) return Future.value();
    final inFlight = _nextInFlight;
    if (inFlight != null) return inFlight;
    if (last) {
      if (_nextFinalTried) return Future.value();
      _nextFinalTried = true;
    } else {
      if (_nextAttempts >= nextEpisodeMaxAttempts) return Future.value();
      final at = _nextLastAttempt;
      if (at != null && debugNow().difference(at) < nextEpisodeRetryGap) {
        return Future.value();
      }
    }
    return _nextInFlight = _fetchNextEpisode().whenComplete(
      () => _nextInFlight = null,
    );
  }

  Future<void> _fetchNextEpisode() async {
    _nextAttempts++;
    _nextLastAttempt = debugNow();
    try {
      final n = await libraryApi.getNextEpisode(itemId);
      if (_disposed) return;
      _nextFetch = _NextFetch.fetched;
      nextEpisode = n;
      _safeNotify();
    } on ApiException catch (e) {
      if (e.code == 404) {
        _nextFetch = _NextFetch.fetched;
      } else {
        _noteNextFailure(e);
      }
    } catch (e) {
      _noteNextFailure(e);
    }
  }

  void _noteNextFailure(Object e) {
    _nextFetch = _NextFetch.failed;
    if (_nextAttempts == 1) debugPrint('next-episode lookup failed: $e');
  }

  /// End of file with a failed lookup: one last try, bounded, so a real end can
  /// still roll over. Re-checks everything the handler checked, since the card
  /// or the viewer may have changed things while the request was out.
  Future<void> _retryThenAdvance() async {
    try {
      await _loadNextEpisode(last: true).timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (_disposed || _tornDown) return;
    if (autoAdvance && nextEpisode != null && !upNextCancelled && !upNextOpen) {
      _requestAdvance();
    }
    _safeNotify();
  }

  /// Rolls into the next episode now (the Up Next "Play Next" action).
  void playNext() => _requestAdvance();

  /// Credits-triggered roll-over (mirrors web ARGY-90): opens the card once
  /// playback is inside the last [upNextLeadSeconds], and retracts it if the
  /// viewer seeks back out. Driven by each player's repaint ticker, since the
  /// controller has no progress event of its own; safe to call repeatedly.
  void maybeAdvance() {
    // Not while the stream is broken or mid-restart, and never on a position
    // that cannot be real (ARGY-283): the card is a prompt about the episode
    // ending, and a dead player's arithmetic is not evidence of that. The
    // window check re-opens it once playback is genuinely back inside it.
    if (fatalError ||
        starting ||
        _pendingOffset != null ||
        !isSanePosition(position)) {
      if (upNextOpen) _closeUpNext();
      return;
    }
    if (autoAdvance &&
        nextEpisode == null &&
        _nextFetchFailed &&
        !_tornDown &&
        catalogDuration > 0 &&
        catalogDuration - position <= upNextLeadSeconds) {
      // Entering the window with a failed lookup (ARGY-264): the ticker calls
      // this constantly, and _loadNextEpisode's gap and cap keep it to a few.
      unawaited(_loadNextEpisode());
    }
    if (!autoAdvance ||
        nextEpisode == null ||
        upNextCancelled ||
        _advancing ||
        _tornDown) {
      return;
    }
    if (catalogDuration <= 0) return;
    // No `remaining > 0` floor: once the card is up it stays up over the final
    // frame until its countdown expires, which is the whole point of the timer.
    if (catalogDuration - position <= upNextLeadSeconds) {
      if (!upNextOpen) _openUpNext();
    } else if (upNextOpen) {
      _closeUpNext();
    }
  }

  /// Shows the card and charges the countdown, always from full. The window is
  /// where the prompt is warranted; how long you get to answer it is not the
  /// window's business (ARGY-207).
  void _openUpNext() {
    upNextOpen = true;
    upNextCountdown = upNextCountdownSeconds;
    _upNextLeftMs = upNextCountdownSeconds * 1000;
    _upNextLastTick = debugNow();
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tickUpNext(),
    );
    _safeNotify();
  }

  void _closeUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    if (!upNextOpen) return;
    upNextOpen = false;
    _safeNotify();
  }

  /// Burns the countdown down in real time, but holds while the viewer has
  /// playback paused — the old position-derived countdown froze on pause for
  /// free, and losing that would roll the episode over while they were away.
  ///
  /// A finished file also reports not-playing, so [_finished] is excluded from
  /// the hold: after a seek into the last couple of seconds the countdown is the
  /// only thing left running, and freezing it would strand the card forever.
  void _tickUpNext() {
    final now = debugNow();
    final elapsed = now.difference(_upNextLastTick ?? now).inMilliseconds;
    _upNextLastTick = now;
    // A broken stream rolls nothing over (ARGY-283).
    if (fatalError) return;
    // Held by a seek (ARGY-261): the full countdown starts when the hold lifts.
    if (upNextHeld) return;
    if (!(debugPlaying ?? videoValue?.isPlaying ?? false) && !_finished) return;
    _upNextLeftMs -= elapsed;
    final secs = (_upNextLeftMs / 1000).ceil().clamp(1, upNextCountdownSeconds);
    if (secs != upNextCountdown) {
      upNextCountdown = secs;
      _safeNotify();
    }
    if (_upNextLeftMs <= 0) _requestAdvance();
  }

  /// Dismisses the Up Next card and stops the end-of-file roll-over for this
  /// episode, leaving the player on the finished episode.
  void cancelUpNext() {
    upNextCancelled = true;
    _closeUpNext();
    _safeNotify();
  }

  void _requestAdvance() {
    // _tornDown: with the player gone [position] collapses to [baseOffset], so a
    // resume that started inside the roll-over window would read as "finished"
    // and advance the series from a screen that is already on its way out.
    if (_advancing || _tornDown || nextEpisode == null) return;
    _advancing = true;
    _closeUpNext();
    _flush();
    onAdvance?.call();
  }

  /// Plays a stowed file from disk (ARGY-49). Deliberately the simplest of the
  /// three paths: no session to negotiate, no playlist to wait on, no token to
  /// carry — the file is already here, which is exactly the property that makes
  /// it work with the network switched off.
  Future<void> _startLocal(double offset) async {
    baseOffset = 0;
    starting = true;
    _safeNotify();
    try {
      // No `subtitles:` here on purpose: captions are driven through
      // selectSubtitle → _applyActiveSubtitle like every other playback path,
      // which keeps one selection mechanism rather than a second, parallel one
      // the Argosy overlay has no way to control.
      await _player!.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.file,
          localPath!,
          bufferingConfiguration: _bufferingConfig,
          notificationConfiguration: _notificationConfig,
        ),
      );
      if (offset > 0) {
        await _player!.seekTo(Duration(milliseconds: (offset * 1000).round()));
      }
      await _player!.play();
    } catch (_) {
      _fail('This stowed copy could not be played. Try stowing it again.');
    } finally {
      starting = false;
      _safeNotify();
    }
  }

  Future<void> _startDirect(double offset) async {
    baseOffset = 0;
    starting = true;
    _safeNotify();
    try {
      // Direct play authenticates via the `?token=` URL (proven in the ARGY-77
      // spike); the Bearer header is sent too, belt-and-suspenders.
      final qp = (token != null && token!.isNotEmpty) ? '?token=$token' : '';
      await _player!.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          '$baseUrl/api/v1/items/$itemId/stream$qp',
          headers: _authHeaders,
          bufferingConfiguration: _bufferingConfig,
          notificationConfiguration: _notificationConfig,
        ),
      );
      if (offset > 0) {
        await _player!.seekTo(Duration(milliseconds: (offset * 1000).round()));
      }
      await _player!.play();
    } catch (_) {
      _fail('This title could not be played.');
    } finally {
      starting = false;
      _safeNotify();
    }
  }

  Future<void> _startTranscodeAt(double offset) async {
    // The choke point (ARGY-283): whatever a caller derived, the session starts
    // somewhere inside the title.
    offset = _resumePoint(offset);
    final gen = ++_restartGen;
    bool stale() => gen != _restartGen;
    final old = _sessionId;
    _sessionId = null;
    // Whether this run got as far as handing the plugin the new source. Until
    // it does, the plugin still holds the previous one.
    var attached = false;
    // Held, not applied: [baseOffset] moves when the new source is up.
    _pendingOffset = offset;
    _windowAtInitSeconds = 0;
    starting = true;
    fatalError = false;
    errorMessage = null;
    // The session's position is absolute, so it has to be re-anchored the moment
    // the offset moves — the player's own clock is about to restart from 0.
    _pushSession(phase: MediaPhase.starting, position: offset);
    _safeNotify();
    try {
      if (old != null) {
        _stopping.add(old);
        // Await the stop before starting the replacement, as web does
        // (ARGY-220). Session ids are deterministic in ⌊startAt⌋ and the server
        // joins a live session with a matching id, so a restart in the same
        // second (Retry, or recovering from an error just after a start) would
        // rejoin the very session this DELETE is in flight to destroy, and be
        // killed by it. Bounded, so a dead link can't hold the restart hostage.
        final prev = _pendingStop;
        _pendingStop = () async {
          if (prev != null) await prev;
          await transcodeApi
              .stopTranscode(old)
              .timeout(const Duration(seconds: 5))
              .catchError((_) {});
          // Pruned once the stop has landed: ids are deterministic, so a later
          // restart at the same second can be handed this id again and must not
          // be mistaken for one that is already being stopped.
          _stopping.remove(old);
        }();
      }
      // A restart that finds no id still waits for the stop the one before it
      // started (ARGY-260), or it would POST into the session being destroyed.
      final pendingStop = _pendingStop;
      if (pendingStop != null) await pendingStop;
      if (stale()) return;
      final sess = await transcodeApi.startTranscode(
        itemId,
        transcodeStartRequest: TranscodeStartRequest(
          startAt: offset,
          hevc: hevc,
          hevcHardware: hevcHardware,
          minHeight: minHeight,
          maxHeight: maxHeight,
        ),
      );
      if (stale() || _tornDown) {
        if (sess != null) _discardSession(sess.id, offset);
        return;
      }
      if (sess == null) {
        _fail("Couldn't start the transcoder.");
        return;
      }
      _sessionId = sess.id;
      final playlistUrl = '$baseUrl${sess.playlistUrl}';
      final ready = await (debugProbe ?? _waitForPlaylist)(
        playlistUrl,
        () => stale() || _tornDown,
      );
      if (_tornDown) {
        // Torn down while this session was starting, ARGY-190's detached path
        // included. Teardown stopped the session it knew about, which wasn't
        // this one, and nothing will touch this one again. A recovery restart
        // racing a teardown is the new way to get here.
        _sessionId = null;
        unawaited(transcodeApi.stopTranscode(sess.id).catchError((_) {}));
        return;
      }
      if (stale()) {
        _discardSession(sess.id, offset);
        return;
      }
      if (!ready) {
        _fail('The transcoder is taking too long. Try again.');
        return;
      }
      _attachGen = gen;
      attached = true;
      if (debugAttach != null) {
        await debugAttach!(playlistUrl);
      } else {
        await _player!.setupDataSource(
          BetterPlayerDataSource(
            BetterPlayerDataSourceType.network,
            playlistUrl,
            videoFormat: BetterPlayerVideoFormat.hls,
            liveStream: true,
            headers: _authHeaders,
            bufferingConfiguration: _bufferingConfig,
            notificationConfiguration: _notificationConfig,
          ),
        );
      }
      if (stale()) {
        _discardSession(sess.id, offset);
        return;
      }
      // Normally `initialized` committed this already; this covers a source that
      // came up without one.
      _commitPendingOffset();
      if (debugAttach == null) await _player!.play();
      if (stale()) return;
      await _applyActiveSubtitle();
      // The winning restart is proof the server is reachable (ARGY-264).
      if (!stale() && _nextFetchFailed) unawaited(_loadNextEpisode());
    } catch (_) {
      if (!stale()) _fail('This stream could not be played.');
    } finally {
      // Only the winning generation owns these: a superseded run clearing
      // `starting` would unmask player exceptions for the restart still live.
      if (!stale()) {
        if (attached) {
          _commitPendingOffset();
        } else {
          // Failed before the swap — a dead link, a server at capacity, a
          // playlist that never came — so the plugin still holds the previous
          // source, whose relative position is measured from the baseOffset it
          // already has. Committing the target here counted that position
          // twice: with ~220s of stale buffer the playhead read 220s further
          // on at every failed restart, which re-armed the recovery budget
          // (it looked like forward progress) and walked the restart offset
          // out of the episode, 220s at a time, for as long as the link was
          // down (ARGY-283).
          _pendingOffset = null;
        }
        starting = false;
        _safeNotify();
      }
    }
  }

  /// Moves [baseOffset] to where the new source starts.
  void _commitPendingOffset() {
    final p = _pendingOffset;
    if (p == null) return;
    baseOffset = p;
    _pendingOffset = null;
  }

  /// Stops a session a superseded restart brought up, unless a newer one is
  /// using it. Ids are deterministic in floor(startAt) and the server joins a
  /// live session with a matching id, so a stop here could kill the winner's.
  void _discardSession(String id, double offset) {
    final target = _pendingOffset;
    final sameSecond = target != null && target.floor() == offset.floor();
    if (_stopping.contains(id) || _sessionId == id || sameSecond) return;
    unawaited(transcodeApi.stopTranscode(id).catchError((_) {}));
  }

  /// Polls the master playlist until ffmpeg has written it (the endpoint returns
  /// 503 until ready), up to ~20s — mirrors the web player's `waitForPlaylist`.
  Future<bool> _waitForPlaylist(String url, bool Function() cancelled) async {
    final headers = _authHeaders;
    for (var i = 0; i < 40; i++) {
      if (cancelled()) return false;
      try {
        final r = await http.get(Uri.parse(url), headers: headers);
        if (r.statusCode == 200) return true;
        if (r.statusCode != 503) return false;
      } catch (_) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  // --- transport -----------------------------------------------------------

  /// Resumes playback. Absolute, not a toggle: media-session callbacks say what
  /// they mean, and a lock-screen "play" arriving while a "pause" is still in
  /// flight would double-flip a toggle back to paused.
  @override
  Future<void> play() async {
    final p = _player;
    if (p == null) return;
    await p.play();
    _safeNotify();
  }

  /// Pauses playback. See [play] for why this isn't expressed as a toggle.
  @override
  Future<void> pause() async {
    final p = _player;
    if (p == null) return;
    await p.pause();
    _safeNotify();
  }

  /// Flips play/pause. For genuinely single-button surfaces — the on-screen
  /// control and the PiP window's lone `RemoteAction`.
  Future<void> togglePlay() async {
    final v = videoValue;
    if (v == null) return;
    await (v.isPlaying ? pause() : play());
  }

  /// Seeks to [target] absolute seconds (implements [MediaSessionTarget.seekTo],
  /// so the lock-screen scrub bar lands here too). Native when the target is already
  /// encoded (direct play, or buffered/encoded transcode); otherwise restarts
  /// the transcode at the new offset.
  ///
  /// NOTE (owed on-device check, per ticket): confirm ExoPlayer honours native
  /// seeks within the live/DVR window under these custom controls. The encoded
  /// bound below is derived defensively from both the reported duration and the
  /// buffered ranges, so a miss only costs a (correct) transcode restart.
  @override
  Future<void> seekTo(double target) async {
    final p = _player;
    if (_tornDown || (p == null && !isTranscode)) return;
    final max = catalogDuration > 0 ? catalogDuration : target;
    final t = target.clamp(0.0, max).toDouble();
    if (!t.isFinite) return;
    // A seek is a fresh decision about where you are, so the card starts over:
    // drop it and let the repaint ticker re-open it — with a full countdown — if
    // the new position is still inside the window (ARGY-207).
    _closeUpNext();
    _noteSeek();
    // Deliberate, so it is the new last good position whatever happens next.
    _lastGoodPosition = t;

    if (!isTranscode) {
      _seekJustIssued = true;
      await p!.seekTo(Duration(milliseconds: (t * 1000).round()));
      _flush();
      return;
    }

    _seekJustIssued = true;
    final rel = t - baseOffset;
    // A restart in flight means the player is mid-swap: its buffered ranges
    // belong to the old source, so always take the restart path (ARGY-260).
    if (p != null &&
        _pendingOffset == null &&
        rel >= 0 &&
        rel <= _encodedSoFarSeconds() + 0.5) {
      await p.seekTo(Duration(milliseconds: (rel * 1000).round()));
      _flush();
    } else {
      // The viewer asking for somewhere else earns a fresh retry budget: a count
      // spent at an earlier position must not fail this one on its first error.
      _recovery.reset(t);
      await _startTranscodeAt(t);
    }
  }

  /// How far the current session is natively seekable (relative timeline): the
  /// encoded window the player initialised against, raised by the furthest
  /// buffered range. Not the plugin's duration — after [pinSessionDuration] that
  /// is the whole session, which says nothing about what ffmpeg has written.
  double _encodedSoFarSeconds() => encodedSoFarFrom(videoValue);

  @visibleForTesting
  double encodedSoFarFrom(VideoPlayerValue? v) {
    var s = _windowAtInitSeconds;
    if (v == null) return s;
    for (final r in v.buffered) {
      final end = r.end.inMilliseconds / 1000.0;
      if (end > s) s = end;
    }
    return s;
  }

  /// Replaces the plugin's duration with the session's real length (ARGY-230).
  ///
  /// better_player_plus reads ExoPlayer's duration once, on `initialized`, and
  /// never again. For an `event` playlist that is still encoding, that reading
  /// is the window ffmpeg had written when the first frame came up — a few
  /// segments, ~16 s. The plugin then treats it as the end of the media: its
  /// `seekTo` clamps any later target back to it, and posts `finished` for the
  /// attempt, because the target was "past the end". Every skip-ahead a minute
  /// or more into a transcode therefore snapped to ~16 s, marked the episode
  /// watched, and rolled into the next one.
  ///
  /// The web player stopped trusting `el.duration` for transcodes in PR #31 and
  /// this controller carried that for the scrub bar ([catalogDuration]); the
  /// plugin's private copy is the half that was missed. The catalog knows how
  /// long the session really is, so tell the plugin. Only ever raises the value:
  /// a session the encoder has already finished reports the true length, and a
  /// catalog runtime that undershoots the file must not chop the end off.
  ///
  /// Direct and offline playback read a complete file, so the plugin's own
  /// reading is right and left alone.
  ///
  /// Typed as the notifier rather than the plugin's `VideoPlayerController`,
  /// which the package does not export — the value is all that is touched.
  @visibleForTesting
  void pinSessionDuration(ValueNotifier<VideoPlayerValue>? vpc) {
    if (vpc == null) return;
    final currentSeconds = (vpc.value.duration?.inMilliseconds ?? 0) / 1000.0;
    _windowAtInitSeconds = currentSeconds;
    if (!isTranscode || isOffline) return;
    final session = catalogDuration - baseOffset;
    if (session <= currentSeconds) return;
    vpc.value = vpc.value.copyWith(
      duration: Duration(milliseconds: (session * 1000).round()),
    );
  }

  /// The overlay's Retry: a fresh session, with a fresh recovery budget, from
  /// where the viewer actually was. Not [baseOffset] (ARGY-283): that is where
  /// the *last restart* began, so a Retry from an error ten minutes into a
  /// session rewound ten minutes — and from a wedged recovery it re-sent the
  /// very offset that had just failed, which is why Retry appeared to do
  /// nothing.
  Future<void> retry() async {
    fatalError = false;
    errorMessage = null;
    _safeNotify();
    final at = _resumePoint();
    if (isTranscode) {
      _recovery.reset(at);
      await _startTranscodeAt(at);
    } else {
      await _startDirect(at);
    }
  }

  // --- subtitles -----------------------------------------------------------

  /// Selects a subtitle track (null = off). When [persist] is true the choice is
  /// saved to the device's preferences.
  Future<void> selectSubtitle(String? trackId, {bool persist = true}) async {
    _activeSubtitleId = trackId;
    _safeNotify();
    await _applyActiveSubtitle();
    if (persist) unawaited(_savePreferredSubtitle(trackId));
  }

  /// (Re)applies the active subtitle, fetching the WebVTT and shifting its cues
  /// by `-baseOffset` so they line up with the (possibly seeked) HLS timeline.
  Future<void> _applyActiveSubtitle() async {
    final ctrl = _player;
    final id = _activeSubtitleId;
    if (ctrl == null) return;
    if (id == null) {
      await ctrl.setupSubtitleSource(
        BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
      );
      return;
    }
    try {
      var vtt = await _subtitleContent(id);
      if (vtt == null) return;
      if (baseOffset > 0) vtt = shiftVtt(vtt, -baseOffset);
      if (_activeSubtitleId != id || _disposed) return; // selection changed
      await ctrl.setupSubtitleSource(
        BetterPlayerSubtitlesSource(
          type: BetterPlayerSubtitlesSourceType.memory,
          name: 'Argosy',
          content: vtt,
          selectedByDefault: true,
        ),
      );
    } catch (_) {
      /* leave subtitles off on failure */
    }
  }

  /// Resolves a track's WebVTT: off the device for a stowed item, from the
  /// server otherwise. Without the local branch a stowed episode would list its
  /// captions and then fail to show any of them, because fetching them is the
  /// one thing that needs the network we don't have.
  Future<String?> _subtitleContent(String trackId) async {
    if (isOffline) {
      for (final s in localSubtitles) {
        if (s.id == trackId) {
          final file = File(s.path);
          return await file.exists() ? await file.readAsString() : null;
        }
      }
      return null;
    }
    return libraryApi.getSubtitle(itemId, trackId);
  }

  void _applyPreferredSubtitle() {
    if (_activeSubtitleId != null) return;
    final p = prefs;
    if (p == null || !p.subtitleEnabled || p.subtitleLanguage == null) return;
    for (final t in subtitles) {
      if (t.language == p.subtitleLanguage) {
        unawaited(selectSubtitle(t.id, persist: false));
        return;
      }
    }
  }

  Future<void> _savePreferredSubtitle(String? trackId) async {
    SubtitleTrack? track;
    if (trackId != null) {
      for (final t in subtitles) {
        if (t.id == trackId) {
          track = t;
          break;
        }
      }
    }
    // Clone-and-mutate so this save can only touch what it owns. Rebuilding the
    // whole object by hand is what dropped captionPosition and reset the
    // viewer's caption placement on every track change (ARGY-208).
    final next = (prefs ?? DevicePreferences(subtitleEnabled: false)).copy()
      ..subtitleEnabled = trackId != null
      ..subtitleLanguage = track?.language ?? prefs?.subtitleLanguage;
    prefs = next;
    try {
      await authApi.setDevicePreferences(next);
    } catch (_) {
      /* best-effort persistence */
    }
  }

  // --- audio tracks (HLS alternate renditions, when present) ----------------

  List<BetterPlayerAsmsAudioTrack> get audioTracks =>
      _player?.betterPlayerAsmsAudioTracks ?? const [];

  /// The id of the active audio rendition, for the picker's selected marker.
  int? _activeAudioTrackId;
  int? get activeAudioTrackId => _activeAudioTrackId;

  /// The language the viewer has settled on (their pick, else the saved pref),
  /// reasserted whenever the HLS renditions (re)parse — e.g. after a transcode
  /// restart on seek — so the choice survives (mirrors the web player, ARGY-128).
  String? _preferredAudioLang;

  /// Selects an audio rendition. When [persist] the language is saved as this
  /// device's preference so it auto-applies on the next title (ARGY-129).
  void selectAudioTrack(
    BetterPlayerAsmsAudioTrack track, {
    bool persist = true,
  }) {
    _player?.setAudioTrack(track);
    _activeAudioTrackId = track.id;
    _preferredAudioLang = track.language;
    _safeNotify();
    if (persist) unawaited(_savePreferredAudio(track.language));
  }

  /// Applies the preferred audio language once the renditions are available: the
  /// viewer's session pick or the saved device pref, else the stream's first
  /// (default) rendition so the picker reflects what's actually playing. No-op
  /// unless there's more than one track.
  void _applyPreferredAudio() {
    final tracks = audioTracks;
    if (tracks.length < 2) return;
    final want = _preferredAudioLang ?? prefs?.audioLanguage;
    if (want != null && want.isNotEmpty) {
      for (final t in tracks) {
        if (t.language == want) {
          _player?.setAudioTrack(t);
          _activeAudioTrackId = t.id;
          _preferredAudioLang = t.language;
          _safeNotify();
          return;
        }
      }
    }
    // No preference (or no match): mark the current default so the sheet shows a
    // selection. The server emits the source-default rendition first (ARGY-127).
    if (_activeAudioTrackId == null) {
      _activeAudioTrackId = tracks.first.id;
      _safeNotify();
    }
  }

  Future<void> _savePreferredAudio(String? lang) async {
    final next = (prefs ?? DevicePreferences(subtitleEnabled: false)).copy()
      ..audioLanguage = lang ?? prefs?.audioLanguage;
    prefs = next;
    try {
      await authApi.setDevicePreferences(next);
    } catch (_) {
      /* best-effort persistence */
    }
  }

  // --- fit (the TV transport's Fit control) ---------------------------------

  /// How the video maps into the screen — letterboxed ([BoxFit.contain]) by
  /// default, toggled to fill ([BoxFit.cover]) by [cycleFit].
  BoxFit videoFit = BoxFit.contain;

  /// Toggles between Fit (letterbox) and Fill (crop-to-fill).
  void cycleFit() {
    videoFit = videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain;
    _player?.setOverriddenFit(videoFit);
    _safeNotify();
  }

  /// "Fit" / "Fill" for the Fit control's label.
  String get fitLabel => videoFit == BoxFit.contain ? 'Fit' : 'Fill';

  // --- progress heartbeat --------------------------------------------------

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _pausedSince = null;
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      final now = DateTime.now();
      if (videoValue?.isPlaying ?? false) {
        _pausedSince = null;
        _flush();
        // Correct any drift in the session's extrapolated position — mostly
        // from stalls, and from a transcode restart moving [baseOffset].
        _pushSession();
        return;
      }
      _pausedSince ??= now;
      // The progress report is also the only thing that touches the session
      // server-side, so a pause that stopped reporting got its session reaped
      // five minutes in, and playback died on resume (ARGY-239). Keep reporting
      // the unchanged position. Teardown cancels this timer and clears the
      // session, so a detached host still leaves it to the reaper (ARGY-190).
      if (keepsPausedSessionAlive(
        hasSession: _sessionId != null,
        pausedSince: _pausedSince,
        now: now,
      )) {
        _flush();
      }
    });
  }

  /// Reports the current absolute position so Beacon + Continue-Watching stay
  /// live. Fire-and-forget, but a failure is no longer simply dropped: a
  /// position reported into a dead socket used to vanish, so an episode watched
  /// on a plane was still sitting at 0% on landing. It is queued instead and
  /// sent on the next successful report (ARGY-49).
  void _flush() {
    final pos = position;
    if (pos <= 0) return;
    // A dead stream has nothing new to say about where the viewer is, and a
    // position outside the title is not a position (ARGY-283). Either would
    // overwrite the resume point the server already holds — and past 95% of
    // the duration it also flips the episode watched, which is how a wedged
    // recovery's heartbeat erased Ashley's place and put Continue at 0:00.
    if (fatalError || !isSanePosition(pos)) return;
    final duration = catalogDuration > 0 ? catalogDuration : null;
    unawaited(
      libraryApi
          .reportProgress(
            itemId,
            ProgressUpdate(positionSeconds: pos, durationSeconds: duration),
          )
          .then((_) async {
            // That call proved the server is reachable — a good moment to drain
            // anything recorded while it wasn't. Retire this item's queued entry
            // first: it is necessarily older than the position just accepted,
            // and the server's write is last-wins, so draining it blind would
            // rewind the resume point we just set.
            final queue = offlineQueue;
            if (queue == null) return;
            await queue.settled(itemId: itemId, positionSeconds: pos);
            await queue.flush(libraryApi);
          })
          .catchError((_) {
            unawaited(
              offlineQueue?.enqueue(
                    itemId: itemId,
                    positionSeconds: pos,
                    durationSeconds: duration,
                  ) ??
                  Future<void>.value(),
            );
            return null;
          }),
    );
  }

  /// Marks the episode watched on finish so it leaves Continue Watching and the
  /// series' On-Deck advances. Queued like [_flush] when the server is out of
  /// reach, so finishing something offline still counts.
  void _markWatched() {
    unawaited(
      libraryApi.setWatched(itemId, WatchedUpdate(watched: true)).catchError((
        _,
      ) {
        unawaited(
          offlineQueue?.enqueue(
                itemId: itemId,
                positionSeconds: position,
                durationSeconds: catalogDuration > 0 ? catalogDuration : null,
                watched: true,
              ) ??
              Future<void>.value(),
        );
        return null;
      }),
    );
  }

  // --- events / helpers ----------------------------------------------------

  void _onEvent(BetterPlayerEvent e) {
    switch (e.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        // A restart tears the data source down and back up; only react to an
        // exception when we're not mid-(re)start.
        if (!starting) _onPlaybackError();
      case BetterPlayerEventType.progress:
        _seekJustIssued = false;
        _accruePlayed();
        // Only a believable reading counts as progress — for the recovery
        // budget, and as the place a later restart may fall back to. A
        // restart's own target is not a reading (ARGY-283).
        final p = position;
        if (isSanePosition(p)) {
          if (!starting && _pendingOffset == null) _lastGoodPosition = p;
          _recovery.progressed(p);
        }
      case BetterPlayerEventType.initialized:
        // The plugin has just taken its one and only duration reading; correct
        // it before any seek can be measured against it (ARGY-230). Runs again
        // after a transcode restart, which recreates the source.
        if (_attachGen == _restartGen) _commitPendingOffset();
        pinSessionDuration(_player?.videoPlayerController);
        // The HLS alternate-audio renditions are parsed by now (ARGY-127); apply
        // the preferred (or default) track and reflect it in the picker. Also
        // reasserts the choice after a transcode restart recreates the source.
        _applyPreferredAudio();
      case BetterPlayerEventType.play:
        // Hold the screen awake while actively playing (ARGY-50). The wakelock
        // is window-scoped, so it lifts automatically once the app backgrounds
        // for audio-only / PiP — no need to react to lifecycle here.
        _setWakelock(true);
        _finished = false;
        _pushSession(phase: MediaPhase.playing);
        // Notify so listeners tracking play/pause (the PiP action icon sync)
        // update — better_player drives these transitions, not togglePlay.
        _safeNotify();
      case BetterPlayerEventType.bufferingStart:
        // Freeze the lock-screen scrubber for the length of the stall; System UI
        // extrapolates position from the last push, so leaving it "playing"
        // would let it drift past the video.
        _pushSession(phase: MediaPhase.buffering);
      case BetterPlayerEventType.bufferingEnd:
        _pushSession();
      case BetterPlayerEventType.finished:
        // The plugin posts `seekTo` then `finished` for a target past its
        // duration, and a source mid-swap can report one too. Neither is the
        // media ending: don't mark watched or roll the episode (ARGY-260).
        // Only a transcode pins a short duration, so only a transcode can post
        // the phantom; and a seek to the very end is a real end of media, which
        // the plugin may report before `progress` has cleared the latch. The
        // phantom always lands far from the catalog end (ARGY-260).
        //
        // Likewise a `finished` with no real playback since the last seek is the
        // echo of a seek, not the media ending: auto-advance is caused by
        // playing (ARGY-261). A genuine end within the slack is exempt from both.
        //
        // And neither is a `finished` from a broken stream, or one read at a
        // position that cannot be in this title (ARGY-283): an empty session
        // ends the instant it opens, and `catalogDuration - position` goes
        // negative past the end, which the old check read as "near the end".
        final pos = position;
        if (fatalError || !isSanePosition(pos)) return;
        final nearEnd =
            catalogDuration > 0 && catalogDuration - pos < _realEndSlackSeconds;
        if (!nearEnd &&
            ((isTranscode &&
                    !isOffline &&
                    (starting || _pendingOffset != null || _seekJustIssued)) ||
                !_playedPastSeek)) {
          return;
        }
        _setWakelock(false);
        _finished = true;
        _pushSession(phase: MediaPhase.finished);
        _flush();
        _markWatched();
        // Roll into the next episode unless the viewer opted out (pref off or
        // card dismissed). Otherwise we leave the player on the finished episode.
        //
        // Not while the card is up: the countdown owns the roll-over, and seeking
        // into the last seconds must still buy a full 15s to answer rather than
        // advancing the instant the file stops. The card sits over the final
        // frame until it expires (ARGY-207).
        if (autoAdvance &&
            nextEpisode != null &&
            !upNextCancelled &&
            !upNextOpen) {
          _requestAdvance();
        } else if (autoAdvance &&
            nextEpisode == null &&
            _nextFetchFailed &&
            !upNextCancelled) {
          unawaited(_retryThenAdvance());
        }
        _safeNotify();
      case BetterPlayerEventType.pause:
        _setWakelock(false);
        _pushSession(phase: MediaPhase.paused);
        _flush();
        _safeNotify();
      case BetterPlayerEventType.seekTo:
        _seekJustIssued = true;
        _noteSeek();
        _pushSession();
        _flush();
      default:
        break;
    }
  }

  /// Routes a player event as if the plugin had posted it. Tests drive the
  /// controller through this, since no native player sits behind it.
  @visibleForTesting
  void handlePlayerEvent(BetterPlayerEvent e) => _onEvent(e);

  /// A fatal player error. On a transcode the likeliest cause is the session
  /// itself being gone, reaped after an uncovered pause or stopped server-side.
  /// ExoPlayer plays out its buffer first, so the 404 lands minutes after the
  /// session died. Restart at the playhead rather than dying (ARGY-239, web's
  /// ARGY-107).
  ///
  /// The plugin doesn't pass the HTTP status through: its message is ExoPlayer's
  /// `PlaybackException`, without the cause. So, like web, this recovers from
  /// any fatal error on a transcode, and [SessionRecovery]'s cap stops one that
  /// isn't transient from looping.
  void _onPlaybackError() {
    if (_tornDown) return;
    if (!isTranscode || isOffline) {
      _fail('Playback stopped unexpectedly.');
      return;
    }
    final at = _resumePoint();
    switch (_recovery.onFatal(at)) {
      case RecoveryDecision.duplicate:
        return;
      case RecoveryDecision.restart:
        // Deferred: this is running inside the plugin's own listener, and the
        // restart replaces the data source that listener belongs to.
        Timer.run(() {
          if (_tornDown) {
            _recovery.settled();
            return;
          }
          unawaited(_startTranscodeAt(at).whenComplete(_recovery.settled));
        });
      case RecoveryDecision.giveUp:
        debugPrint(
          'argosy: giving up after ${_recovery.attempts} recovery attempts '
          'without playback',
        );
        // Don't bury what the last restart said ("Couldn't start the
        // transcoder.") under a generic message.
        if (!fatalError) _fail('Playback stopped unexpectedly.');
    }
  }

  void _setWakelock(bool on) {
    // Fire-and-forget; the plugin no-ops if already in the requested state.
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}),
    );
  }

  void _fail(String message) {
    fatalError = true;
    errorMessage = message;
    // The card is about the episode ending; the stream breaking is not that.
    _closeUpNext();
    _safeNotify();
  }

  /// The retry budget, for tests that assert Retry hands out a fresh one.
  @visibleForTesting
  SessionRecovery get debugRecovery => _recovery;

  @visibleForTesting
  bool get debugHasSession => _sessionId != null;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Dismissing the Android PiP window finishes the host activity, and the
  /// widget tree is never torn down with it — so [dispose] doesn't run and the
  /// server is left holding a live ffmpeg (ARGY-190).
  ///
  /// The engine survives because `AudioServiceActivity` hands `FlutterActivity` a
  /// *cached* engine (ARGY-87), which makes `shouldDestroyEngineWithHost()` false.
  /// That keeps Dart alive to make this call — but it also means the 10s progress
  /// heartbeat keeps running, and every report re-touches the session server-side,
  /// so the idle reaper never collects it either. Detaching is the only signal
  /// there is: `FlutterActivity.onDestroy` → `onDetach()` → `appIsDetached()`.
  ///
  /// PiP itself reports `inactive`/`paused`, never `detached`, so floating the
  /// video doesn't trip this.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.detached || _disposed || _tornDown) return;
    _teardown();
    // The route has to go too: the activity is gone but this widget tree isn't,
    // so relaunching re-attaches to the same engine and would rebuild the player
    // screen around a controller whose native player is already disposed.
    onHostDetached?.call();
  }

  /// Releases everything this controller owns off the widget tree. Runs once:
  /// the detached path calls it, and so does the [dispose] that follows the pop.
  /// The guard is not just tidiness — with [_player] gone, [position] collapses
  /// to [baseOffset], so a second [_flush] would report the *start* of the
  /// transcode session and rewind the resume point that the first one just saved.
  void _teardown() {
    if (_tornDown) return;
    _tornDown = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    _upNextTimer?.cancel();
    _upNextTimer = null;
    _setWakelock(false);
    _flush();
    // Ahead of the audio-handler detach: that releases the foreground service,
    // and on the detached path the process is only alive *because* of it — a
    // request started after it goes is racing process death.
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      unawaited(transcodeApi.stopTranscode(sid).catchError((_) {}));
    }
    // Identity-arbitrated: on series auto-advance this runs *after* the next
    // episode's controller has already attached, and must not tear down its
    // session.
    argosyAudioHandler?.detach(this);
    // forceDispose: the controller is configured autoDispose:false (we own the
    // lifecycle), and a plain dispose() is a no-op in that mode — without this
    // the native player keeps playing audio after the screen is popped.
    _player?.dispose(forceDispose: true);
    _player = null;
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _teardown();
    super.dispose();
  }
}

/// Maps saved per-device caption preferences to better_player_plus's subtitle
/// rendering config (mirrors the web `::cue` styling fields).
BetterPlayerSubtitlesConfiguration _captionConfig(DevicePreferences? p) {
  final scale = (p?.captionScale ?? 1).toDouble();
  final color = _parseHexColor(p?.captionColor) ?? Colors.white;
  final bg = switch (p?.captionBackground) {
    DevicePreferencesCaptionBackgroundEnum.solid => Colors.black,
    DevicePreferencesCaptionBackgroundEnum.none => Colors.transparent,
    _ => Colors.black54, // translucent (default)
  };
  // Vertical placement as bottom padding (better_player is bottom-anchored):
  // bottom sits near the edge, raised (default) lifts above the controls, higher
  // pushes further up the frame (ARGY-60).
  final bottomPadding = switch (p?.captionPosition) {
    DevicePreferencesCaptionPositionEnum.bottom => 12.0,
    DevicePreferencesCaptionPositionEnum.higher => 88.0,
    _ => 48.0, // raised (default)
  };
  return BetterPlayerSubtitlesConfiguration(
    fontSize: 16 * scale,
    fontColor: color,
    backgroundColor: bg,
    // Keep an outline when there's no box behind the text, for legibility.
    outlineEnabled: bg == Colors.transparent,
    fontFamily: 'HankenGrotesk',
    bottomPadding: bottomPadding,
  );
}

Color? _parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
