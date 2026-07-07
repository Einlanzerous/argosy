import 'dart:async';

import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

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
class PlaybackController extends ChangeNotifier {
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
    required this.prefs,
    this.notificationAuthor,
    this.artworkUrl,
  });

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

  /// Whether the device advertised 4K-HEVC decode to the transcoder.
  final bool hevc;

  /// Subtitle tracks available for the item (populated up front).
  final List<SubtitleTrack> subtitles;

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

  bool _advancing = false;

  /// Whether series auto-advance is enabled for this device (default on).
  bool get autoAdvance => prefs?.seriesAutoAdvance ?? true;

  /// Seconds before the end at which the Up Next / Play Next card surfaces.
  static const upNextLeadSeconds = 40;

  /// Seconds before the end at which we auto-roll into the next episode. Short of
  /// the literal end (mirrors web ARGY-90) so the card shows a
  /// [upNextLeadSeconds] − [upNextTailSeconds] = 15s countdown that actually
  /// triggers the advance, rather than a timer that just mirrors the time left to
  /// the finished event. Manual Play Next jumps immediately.
  static const upNextTailSeconds = 25;

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

  Map<String, String> get _authHeaders =>
      (token != null && token!.isNotEmpty) ? {'Authorization': 'Bearer $token'} : {};

  /// Lock-screen / notification media controls + background audio (ARGY-50).
  /// Enabling this also starts better_player_plus's `mediaPlayback` foreground
  /// service and, as a side effect, disables the library's auto-pause-on-
  /// background — which is exactly what we want for background playback.
  BetterPlayerNotificationConfiguration get _notificationConfig =>
      BetterPlayerNotificationConfiguration(
        showNotification: true,
        title: title,
        author: notificationAuthor,
        imageUrl: artworkUrl,
        activityName: 'MainActivity',
      );

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
        controlsConfiguration:
            const BetterPlayerControlsConfiguration(showControls: false),
        subtitlesConfiguration: _captionConfig(prefs),
      ),
    )..addEventsListener(_onEvent);

    if (isTranscode) {
      await _startTranscodeAt(offset);
    } else {
      await _startDirect(offset);
    }
    _startHeartbeat();
    _applyPreferredSubtitle();
    if (autoAdvance) unawaited(_loadNextEpisode());
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

  /// Credits-triggered roll-over (mirrors web ARGY-90): once playback is within
  /// [upNextTailSeconds] of the end, advance instead of waiting for the finished
  /// event, so the countdown actually does something. Driven by the overlay's
  /// repaint ticker; safe to call repeatedly — [_requestAdvance] guards against
  /// double-firing, and a dismissed card or disabled pref opts out.
  void maybeAdvance() {
    if (!autoAdvance || nextEpisode == null || upNextCancelled || _advancing) {
      return;
    }
    if (catalogDuration <= 0) return;
    final remaining = catalogDuration - position;
    if (remaining > 0 && remaining <= upNextTailSeconds) _requestAdvance();
  }

  /// Dismisses the Up Next card and stops the end-of-file roll-over for this
  /// episode, leaving the player on the finished episode.
  void cancelUpNext() {
    upNextCancelled = true;
    _safeNotify();
  }

  void _requestAdvance() {
    if (_advancing || nextEpisode == null) return;
    _advancing = true;
    _flush();
    onAdvance?.call();
  }

  Future<void> _startDirect(double offset) async {
    baseOffset = 0;
    starting = true;
    _safeNotify();
    try {
      // Direct play authenticates via the `?token=` URL (proven in the ARGY-77
      // spike); the Bearer header is sent too, belt-and-suspenders.
      final qp = (token != null && token!.isNotEmpty) ? '?token=$token' : '';
      await _player!.setupDataSource(BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        '$baseUrl/api/v1/items/$itemId/stream$qp',
        headers: _authHeaders,
        notificationConfiguration: _notificationConfig,
      ));
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
    _safeNotify();
    try {
      final sess = await transcodeApi.startTranscode(
        itemId,
        transcodeStartRequest: TranscodeStartRequest(startAt: offset, hevc: hevc),
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
      await _player!.setupDataSource(BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        playlistUrl,
        videoFormat: BetterPlayerVideoFormat.hls,
        liveStream: true,
        headers: _authHeaders,
        notificationConfiguration: _notificationConfig,
      ));
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

  Future<void> togglePlay() async {
    final p = _player;
    final v = videoValue;
    if (p == null || v == null) return;
    if (v.isPlaying) {
      await p.pause();
    } else {
      await p.play();
    }
    _safeNotify();
  }

  /// Seeks to [target] absolute seconds. Native when the target is already
  /// encoded (direct play, or buffered/encoded transcode); otherwise restarts
  /// the transcode at the new offset.
  ///
  /// NOTE (owed on-device check, per ticket): confirm ExoPlayer honours native
  /// seeks within the live/DVR window under these custom controls. The encoded
  /// bound below is derived defensively from both the reported duration and the
  /// buffered ranges, so a miss only costs a (correct) transcode restart.
  Future<void> seekTo(double target) async {
    final p = _player;
    if (p == null) return;
    final max = catalogDuration > 0 ? catalogDuration : target;
    final t = target.clamp(0.0, max).toDouble();

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
      var vtt = await libraryApi.getSubtitle(itemId, id);
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
  void selectAudioTrack(BetterPlayerAsmsAudioTrack track, {bool persist = true}) {
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
      if (videoValue?.isPlaying ?? false) _flush();
    });
  }

  /// Reports the current absolute position so Beacon + Continue-Watching stay
  /// live. Fire-and-forget; failures are swallowed.
  void _flush() {
    final pos = position;
    if (pos <= 0) return;
    unawaited(
      libraryApi
          .reportProgress(
            itemId,
            ProgressUpdate(
              positionSeconds: pos,
              durationSeconds: catalogDuration > 0 ? catalogDuration : null,
            ),
          )
          .catchError((_) => null),
    );
  }

  /// Marks the episode watched on finish so it leaves Continue Watching and the
  /// series' On-Deck advances. Fire-and-forget, mirroring the web player.
  void _markWatched() {
    unawaited(
      libraryApi
          .setWatched(itemId, WatchedUpdate(watched: true))
          .catchError((_) => null),
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
        // Notify so listeners tracking play/pause (the PiP action icon sync)
        // update — better_player drives these transitions, not togglePlay.
        _safeNotify();
      case BetterPlayerEventType.finished:
        _setWakelock(false);
        _flush();
        _markWatched();
        // Roll into the next episode unless the viewer opted out (pref off or
        // card dismissed). Otherwise we leave the player on the finished episode.
        if (autoAdvance && nextEpisode != null && !upNextCancelled) {
          _requestAdvance();
        }
        _safeNotify();
      case BetterPlayerEventType.pause:
        _setWakelock(false);
        _flush();
        _safeNotify();
      case BetterPlayerEventType.seekTo:
        _flush();
      default:
        break;
    }
  }

  void _setWakelock(bool on) {
    // Fire-and-forget; the plugin no-ops if already in the requested state.
    unawaited((on ? WakelockPlus.enable() : WakelockPlus.disable())
        .catchError((_) {}));
  }

  void _fail(String message) {
    fatalError = true;
    errorMessage = message;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _setWakelock(false);
    _flush();
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      unawaited(transcodeApi.stopTranscode(sid).catchError((_) {}));
    }
    // forceDispose: the controller is configured autoDispose:false (we own the
    // lifecycle), and a plain dispose() is a no-op in that mode — without this
    // the native player keeps playing audio after the screen is popped.
    _player?.dispose(forceDispose: true);
    _player = null;
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
