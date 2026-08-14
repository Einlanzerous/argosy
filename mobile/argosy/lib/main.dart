import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/player/argosy_audio_handler.dart';
import 'platform/device_capabilities.dart';
import 'platform/device_type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The port the download service talks back over (ARGY-201). Must be opened
  // before anything can attach to a transfer already running — including one
  // this launch of the app did not start.
  FlutterForegroundTask.initCommunicationPort();
  await _initMediaSession();
  // Resolve the device type once up front so the root can synchronously pick the
  // TV (10-foot, D-pad) shell vs. the touch shell (ARGY-51).
  final isTv = await DeviceCapabilities.isTelevision();
  if (isTv) {
    // Always paint focus highlights on a TV. Flutter's default highlight mode
    // follows the last input kind and flips to `touch` (no focus rings) on any
    // pointer event — which on a 10-foot D-pad UI leaves the user unable to see
    // what's focused even though focus traversal is working fine.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }
  runApp(
    ProviderScope(
      overrides: [isTelevisionProvider.overrideWithValue(isTv)],
      child: const ArgosyApp(),
    ),
  );
}

/// Brings up the platform media session that backs the lock-screen / Quick
/// Settings transport controls (ARGY-87). Must run before `runApp` — the
/// underlying service is bound once, for the process's lifetime.
///
/// **Android only.** ARGY-87 is an Android bug; on iOS better_player_plus's own
/// `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` path already works, and
/// running both would mean two things publishing now-playing info. See
/// `PlaybackController._notificationConfig`.
///
/// A failure here is not fatal: [argosyAudioHandler] stays null, every call site
/// no-ops, and playback runs without a media notification rather than not
/// running at all.
Future<void> _initMediaSession() async {
  if (!Platform.isAndroid) return;
  try {
    argosyAudioHandler = await AudioService.init(
      builder: ArgosyAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.dodson.argosy.playback',
        androidNotificationChannelName: 'Playback',
        androidNotificationChannelDescription:
            'Transport controls for whatever Argosy is playing.',
        // Monochrome mark; the default (mipmap/ic_launcher) renders as a white
        // blob because Android masks a small icon to its alpha channel.
        androidNotificationIcon: 'drawable/ic_stat_argosy',
        notificationColor: Color(0xFFC99A4E),
        // Posters are far larger than the ~320px the system actually renders,
        // and the bitmap crosses a Binder transaction to System UI.
        artDownscaleWidth: 320,
        artDownscaleHeight: 320,
        // NB: `androidStopForegroundOnPause` is deliberately left at its default
        // of true — dropping out of the foreground on pause is load-bearing, not
        // incidental. Setting it false (so a later play never has to start a
        // foreground service from the background) strands the notification: a
        // foreground service's notification cannot be cancelled, and
        // audio_service's `stopSelf()` on the idle transition can't destroy the
        // service while the activity is still bound to it — so leaving the
        // player left a dead, undismissable notification behind. Resuming is
        // safe either way: Android grants a ~10s foreground-service allowlist
        // whenever a MediaSession callback fires, and every resume path here is
        // one (lock-screen button, notification action, or media key).
      ),
    );
  } catch (_) {
    argosyAudioHandler = null;
  }
}
