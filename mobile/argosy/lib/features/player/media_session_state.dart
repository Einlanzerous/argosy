import 'package:audio_service/audio_service.dart';

/// Pure derivation of the lock-screen / notification media session's state from
/// what [PlaybackController] knows (ARGY-87).
///
/// Kept free of platform channels and of the player itself so every rule below
/// is unit-testable. The rules exist because the session is fed from Dart rather
/// than bound to the ExoPlayer: playback here is transcode-backed, so the
/// player's own timeline is *relative* (position resets to 0 after a seek
/// restart, and an event playlist only knows the encoded-so-far duration).
/// Everything published here is absolute media time against the catalog runtime.

/// Which way the transport is currently pointing. Ordered by precedence:
/// [starting] and [buffering] outrank [playing], because a stalled player that
/// reports speed 1.0 makes the lock-screen scrubber run ahead of the video.
enum MediaPhase { starting, buffering, playing, paused, finished }

/// The identity + metadata half of the session — the bits that only change when
/// the title does.
class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    required this.durationSeconds,
    this.subtitle,
    this.artworkUrl,
  });

  final String id;

  /// Primary line: the episode's own name, or the film's title.
  final String title;

  /// Secondary line, e.g. `Futurama · Season 1, Ep 1`.
  final String? subtitle;

  /// Absolute artwork URL. The server serves artwork unauthenticated, so no
  /// token is appended and audio_service can fetch it directly.
  final String? artworkUrl;

  /// Catalog runtime. Zero (or negative) means unknown — see [toMediaItem].
  final double durationSeconds;

  bool get hasDuration => durationSeconds > 0;

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: subtitle,
        // A zero duration renders a degenerate zero-width scrubber, so an
        // unknown runtime must be *absent*, not Duration.zero.
        duration: hasDuration ? _seconds(durationSeconds) : null,
        artUri: _artUri(artworkUrl),
      );
}

/// Builds the [PlaybackState] to publish for [phase] at [positionSeconds] of
/// absolute media time.
///
/// [speed] is the player's reported rate; it is forced to 0 whenever we aren't
/// actually advancing, so System UI — which extrapolates position from the
/// update timestamp rather than re-reading it — holds the scrubber still.
PlaybackState mediaPlaybackState({
  required MediaPhase phase,
  required double positionSeconds,
  required NowPlaying now,
  double bufferedSeconds = 0,
  double speed = 1.0,
}) {
  final playing = phase == MediaPhase.playing;
  final duration = now.durationSeconds;
  final clamped = duration > 0
      ? positionSeconds.clamp(0.0, duration).toDouble()
      : (positionSeconds < 0 ? 0.0 : positionSeconds);

  return PlaybackState(
    processingState: switch (phase) {
      MediaPhase.starting => AudioProcessingState.loading,
      MediaPhase.buffering => AudioProcessingState.buffering,
      MediaPhase.finished => AudioProcessingState.completed,
      MediaPhase.playing || MediaPhase.paused => AudioProcessingState.ready,
    },
    playing: playing,
    // Android 13+ derives the transport buttons from the session, not from the
    // notification's own actions.
    controls: [playing ? MediaControl.pause : MediaControl.play],
    androidCompactActionIndices: const [0],
    // The seek bar only appears when the session advertises seeking *and* the
    // item carries a duration; without a runtime there is nothing to scrub over.
    systemActions: now.hasDuration
        ? const {MediaAction.seek, MediaAction.playPause}
        : const {MediaAction.playPause},
    updatePosition: _seconds(phase == MediaPhase.finished && duration > 0
        ? duration
        : clamped),
    bufferedPosition: _seconds(bufferedSeconds < 0 ? 0 : bufferedSeconds),
    speed: playing ? speed : 0.0,
  );
}

Duration _seconds(double s) => Duration(milliseconds: (s * 1000).round());

Uri? _artUri(String? url) {
  if (url == null || url.isEmpty) return null;
  return Uri.tryParse(url);
}
