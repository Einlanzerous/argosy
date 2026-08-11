import 'package:audio_service/audio_service.dart';

import 'media_session_state.dart';

/// The transport surface a media session drives. [PlaybackController] implements
/// it; keeping it abstract here is what lets the handler live below the
/// controller in the import graph.
///
/// Every method is **absolute**, deliberately: a lock-screen "play" arriving
/// while a "pause" is still in flight would double-flip a toggle. (The PiP
/// window's single `RemoteAction` genuinely is a toggle and keeps using
/// `togglePlay`.)
abstract class MediaSessionTarget {
  Future<void> play();
  Future<void> pause();

  /// Seeks to [seconds] of *absolute* media time.
  Future<void> seekTo(double seconds);
}

/// Owns Argosy's platform media session — the lock-screen / Quick Settings
/// transport controls and the single notification that backs them (ARGY-87).
///
/// One instance for the app's lifetime, created by `AudioService.init` in
/// `main`. It holds no player: playback lives in whichever [PlaybackController]
/// is currently attached, and this class only relays commands to it and
/// republishes the state that controller reports.
///
/// Attachment is **identity-arbitrated**. Series auto-advance does a
/// `pushReplacement`, and the outgoing route's `dispose` runs ~300ms *after* the
/// incoming route has already attached — so a detach that didn't check identity
/// would tear down the session the next episode just set up.
class ArgosyAudioHandler extends BaseAudioHandler {
  MediaSessionTarget? _current;

  /// Whether [target] is the controller currently driving the session.
  bool isCurrent(MediaSessionTarget target) => identical(_current, target);

  /// Binds [target] as the live transport and publishes its metadata. Safe to
  /// call again for the same target to refresh metadata mid-playback.
  void attach(MediaSessionTarget target, NowPlaying now) {
    _current = target;
    mediaItem.add(now.toMediaItem());
  }

  /// Publishes a new transport state for [target]. Dropped if [target] has been
  /// superseded, so a late event from an outgoing episode can't overwrite the
  /// incoming one's scrubber.
  void push(MediaSessionTarget target, PlaybackState state) {
    if (!isCurrent(target)) return;
    playbackState.add(state);
  }

  /// Releases the session if — and only if — [target] still owns it.
  void detach(MediaSessionTarget target) {
    if (!isCurrent(target)) return;
    _current = null;
    mediaItem.add(null);
    // Default-constructed is the idle state: not playing, no controls, no
    // duration — which is what dismisses the notification.
    playbackState.add(PlaybackState());
  }

  @override
  Future<void> play() async => _current?.play();

  @override
  Future<void> pause() async => _current?.pause();

  @override
  Future<void> seek(Duration position) async =>
      _current?.seekTo(position.inMilliseconds / 1000.0);

  /// Swiping the notification away (or the system asking us to stop) pauses
  /// rather than tearing the player down — the player screen may still be
  /// mounted behind the lock screen, and [detach] is the controller's job.
  @override
  Future<void> stop() async => _current?.pause();
}

/// Set once by `AudioService.init` in `main`. Null when the media session
/// couldn't be initialised (or on a platform that has none), in which case every
/// call site degrades to a no-op rather than crashing playback.
ArgosyAudioHandler? argosyAudioHandler;
