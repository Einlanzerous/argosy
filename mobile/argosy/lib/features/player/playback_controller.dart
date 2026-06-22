import 'dart:async';

import 'package:argosy_api/api.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
    required this.catalogDuration,
    required this.isTranscode,
    required this.hevc,
    required this.subtitles,
    required this.prefs,
  });

  final LibraryApi libraryApi;
  final TranscodeApi transcodeApi;
  final AuthApi authApi;
  final String baseUrl;
  final String? token;
  final String itemId;

  /// Total runtime from the catalog, in seconds (the scrub bar's domain).
  final double catalogDuration;

  /// Whether playback goes through an HLS transcode session vs. a direct stream.
  final bool isTranscode;

  /// Whether the device advertised 4K-HEVC decode to the transcoder.
  final bool hevc;

  /// Subtitle tracks available for the item (populated up front).
  final List<SubtitleTrack> subtitles;

  DevicePreferences? prefs;

  BetterPlayerController? _player;
  BetterPlayerController? get player => _player;

  /// The latest frame of video state (position, buffering, playing…) for the
  /// overlay. Null until the first data source is set up.
  VideoPlayerValue? get videoValue => _player?.videoPlayerController?.value;

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

  void selectAudioTrack(BetterPlayerAsmsAudioTrack track) {
    _player?.setAudioTrack(track);
    _safeNotify();
  }

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

  // --- events / helpers ----------------------------------------------------

  void _onEvent(BetterPlayerEvent e) {
    switch (e.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        // A restart tears the data source down and back up; only surface an
        // exception when we're not mid-(re)start.
        if (!starting) _fail('Playback stopped unexpectedly.');
      case BetterPlayerEventType.finished:
      case BetterPlayerEventType.pause:
      case BetterPlayerEventType.seekTo:
        _flush();
      default:
        break;
    }
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
  return BetterPlayerSubtitlesConfiguration(
    fontSize: 16 * scale,
    fontColor: color,
    backgroundColor: bg,
    // Keep an outline when there's no box behind the text, for legibility.
    outlineEnabled: bg == Colors.transparent,
    fontFamily: 'HankenGrotesk',
    bottomPadding: 48,
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
