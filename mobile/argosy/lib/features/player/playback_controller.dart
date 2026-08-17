import 'dart:async';
import 'dart:io';

import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../stow/offline_progress_queue.dart';
import 'argosy_audio_handler.dart';
import 'media_session_state.dart';
import 'vtt.dart';

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

  /// Whether the Up Next card should be showing, and the seconds left on its
  /// countdown. Both players render from these rather than deriving them, so the
  /// countdown has one owner and one timer.
  bool upNextOpen = false;
  int upNextCountdown = upNextCountdownSeconds;

  Timer? _upNextTimer;
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
  VideoPlayerValue? get videoValue => _player?.videoPlayerController?.value;

  /// True once the player has a data source whose first frame is ready to
  /// render. Deliberately avoids better_player's `isVideoInitialized()`, which
  /// *throws* StateError while the data source is still being set up — the
  /// source of a transient red error frame during the loading spinner.
  bool get isReady => videoValue?.initialized ?? false;

  String? _sessionId;

  /// The transcode StartAt for the current session (0 for direct play). Added
  /// to the player's relative position to get absolute media time.
  double baseOffset = 0;

  /// True while a session is (re)starting — the overlay shows a spinner.
  bool starting = false;

  /// Set when playback hits an unrecoverable error; the overlay offers a retry.
  bool fatalError = false;
  String? errorMessage;

  String? _activeSubtitleId;
  String? get activeSubtitleId => _activeSubtitleId;

  Timer? _heartbeat;
  bool _disposed = false;
  bool _tornDown = false;

  Map<String, String> get _authHeaders => (token != null && token!.isNotEmpty)
      ? {'Authorization': 'Bearer $token'}
      : {};

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
    final ms = videoValue?.position.inMilliseconds ?? 0;
    return baseOffset + ms / 1000.0;
  }

  // --- lifecycle -----------------------------------------------------------

  /// Begins playback at [offset] seconds of absolute media time. For transcode
  /// this starts ffmpeg at that offset; for direct play it seeks the element.
  Future<void> start(double offset) async {
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
    if (autoAdvance && !isOffline) unawaited(_loadNextEpisode());
  }

  /// Fetches the next episode for auto-advance. A 404 (last episode, or not a
  /// series episode) just leaves [nextEpisode] null — no card, no roll-over.
  Future<void> _loadNextEpisode() async {
    try {
      final n = await libraryApi.getNextEpisode(itemId);
      if (_disposed) return;
      nextEpisode = n;
      _safeNotify();
    } catch (_) {
      /* no next episode */
    }
  }

  /// Rolls into the next episode now (the Up Next "Play Next" action).
  void playNext() => _requestAdvance();

  /// Credits-triggered roll-over (mirrors web ARGY-90): opens the card once
  /// playback is inside the last [upNextLeadSeconds], and retracts it if the
  /// viewer seeks back out. Driven by each player's repaint ticker, since the
  /// controller has no progress event of its own; safe to call repeatedly.
  void maybeAdvance() {
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
    _upNextLastTick = DateTime.now();
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
    final now = DateTime.now();
    final elapsed = now.difference(_upNextLastTick ?? now).inMilliseconds;
    _upNextLastTick = now;
    if (!(videoValue?.isPlaying ?? false) && !_finished) return;
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
    final old = _sessionId;
    _sessionId = null;
    if (old != null) {
      unawaited(transcodeApi.stopTranscode(old).catchError((_) {}));
    }
    baseOffset = offset;
    starting = true;
    fatalError = false;
    errorMessage = null;
    // The session's position is absolute, so it has to be re-anchored the moment
    // the offset moves — the player's own clock is about to restart from 0.
    _pushSession(phase: MediaPhase.starting, position: offset);
    _safeNotify();
    try {
      final sess = await transcodeApi.startTranscode(
        itemId,
        transcodeStartRequest: TranscodeStartRequest(
          startAt: offset,
          hevc: hevc,
        ),
      );
      if (sess == null) {
        _fail("Couldn't start the transcoder.");
        return;
      }
      _sessionId = sess.id;
      final playlistUrl = '$baseUrl${sess.playlistUrl}';
      if (!await _waitForPlaylist(playlistUrl)) {
        _fail('The transcoder is taking too long. Try again.');
        return;
      }
      if (_disposed) return;
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
      await _player!.play();
      await _applyActiveSubtitle();
    } catch (_) {
      _fail('This stream could not be played.');
    } finally {
      starting = false;
      _safeNotify();
    }
  }

  /// Polls the master playlist until ffmpeg has written it (the endpoint returns
  /// 503 until ready), up to ~20s — mirrors the web player's `waitForPlaylist`.
  Future<bool> _waitForPlaylist(String url) async {
    final headers = _authHeaders;
    for (var i = 0; i < 40; i++) {
      if (_disposed) return false;
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
    if (p == null) return;
    final max = catalogDuration > 0 ? catalogDuration : target;
    final t = target.clamp(0.0, max).toDouble();
    // A seek is a fresh decision about where you are, so the card starts over:
    // drop it and let the repaint ticker re-open it — with a full countdown — if
    // the new position is still inside the window (ARGY-207).
    _closeUpNext();

    if (!isTranscode) {
      await p.seekTo(Duration(milliseconds: (t * 1000).round()));
      _flush();
      return;
    }

    final rel = t - baseOffset;
    if (rel >= 0 && rel <= _encodedSoFarSeconds() + 0.5) {
      await p.seekTo(Duration(milliseconds: (rel * 1000).round()));
      _flush();
    } else {
      await _startTranscodeAt(t);
    }
  }

  /// How far the current session is natively seekable (relative timeline), taken
  /// as the max of the reported duration (event playlist = encoded-so-far) and
  /// the furthest buffered range.
  double _encodedSoFarSeconds() {
    final v = videoValue;
    if (v == null) return 0;
    var ms = v.duration?.inMilliseconds ?? 0;
    for (final r in v.buffered) {
      if (r.end.inMilliseconds > ms) ms = r.end.inMilliseconds;
    }
    return ms / 1000.0;
  }

  Future<void> retry() async {
    fatalError = false;
    errorMessage = null;
    _safeNotify();
    if (isTranscode) {
      await _startTranscodeAt(baseOffset);
    } else {
      await _startDirect(position);
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
    final next = DevicePreferences(
      subtitleEnabled: trackId != null,
      subtitleLanguage: track?.language ?? prefs?.subtitleLanguage,
      audioLanguage: prefs?.audioLanguage,
      captionScale: prefs?.captionScale,
      captionColor: prefs?.captionColor,
      captionBackground: prefs?.captionBackground,
      // Preserve auto-advance so changing subtitles mid-playback doesn't reset it.
      seriesAutoAdvance: prefs?.seriesAutoAdvance,
    );
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
    final next = DevicePreferences(
      subtitleEnabled: prefs?.subtitleEnabled ?? false,
      subtitleLanguage: prefs?.subtitleLanguage,
      audioLanguage: lang ?? prefs?.audioLanguage,
      captionScale: prefs?.captionScale,
      captionColor: prefs?.captionColor,
      captionBackground: prefs?.captionBackground,
      captionPosition: prefs?.captionPosition,
      seriesAutoAdvance: prefs?.seriesAutoAdvance,
    );
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
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      if (videoValue?.isPlaying ?? false) {
        _flush();
        // Correct any drift in the session's extrapolated position — mostly
        // from stalls, and from a transcode restart moving [baseOffset].
        _pushSession();
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
        // A restart tears the data source down and back up; only surface an
        // exception when we're not mid-(re)start.
        if (!starting) _fail('Playback stopped unexpectedly.');
      case BetterPlayerEventType.initialized:
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
        }
        _safeNotify();
      case BetterPlayerEventType.pause:
        _setWakelock(false);
        _pushSession(phase: MediaPhase.paused);
        _flush();
        _safeNotify();
      case BetterPlayerEventType.seekTo:
        _pushSession();
        _flush();
      default:
        break;
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
    _safeNotify();
  }

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
