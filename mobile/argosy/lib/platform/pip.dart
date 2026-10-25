import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Drives Android Picture-in-Picture through a platform channel (mirrors
/// [DeviceCapabilities]'s channel pattern). PiP is entered natively — from the
/// player's PiP button ([enter]) and automatically when the user leaves the app
/// while playing (the native `onUserLeaveHint`). The native side gates that
/// auto-enter on [setActive], which the player screen toggles on/off as it
/// mounts and unmounts.
///
/// iOS PiP is AVKit-driven and handled by better_player_plus directly (see the
/// player screen), so every method here is Android-only and degrades to a safe
/// no-op elsewhere.
class PiP {
  PiP._();

  static const _channel = MethodChannel('dev.dodson.argosy/pip');

  static bool? _supported;
  static bool _handlerInstalled = false;
  static void Function(bool inPip)? _onChanged;
  static void Function()? _onToggle;

  /// Whether this device exposes a system PiP feature. Cached after the first
  /// call. Always false off-Android.
  static Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    if (!Platform.isAndroid) return _supported = false;
    try {
      final ok = await _channel.invokeMethod<bool>('isSupported');
      return _supported = ok ?? false;
    } on PlatformException {
      return _supported = false;
    } on MissingPluginException {
      return _supported = false;
    }
  }

  /// Marks whether a player is foregrounded with active playback, gating the
  /// native auto-enter-on-leave. Safe to call when PiP is unsupported.
  static Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setActive', active);
    } on PlatformException {
      /* ignore */
    } on MissingPluginException {
      /* ignore */
    }
  }

  /// Enters PiP now (the player's PiP button). No-op when unsupported.
  static Future<void> enter() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('enter');
    } on PlatformException {
      /* ignore */
    } on MissingPluginException {
      /* ignore */
    }
  }

  /// Reports the current play/pause state so the PiP window's play/pause action
  /// shows the right icon. Safe to call when PiP is unsupported.
  static Future<void> setPlaying(bool playing) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setPlaying', playing);
    } on PlatformException {
      /* ignore */
    } on MissingPluginException {
      /* ignore */
    }
  }

  /// Registers handlers: [onChanged] fires with the current PiP mode whenever it
  /// changes (so the player can hide its overlay chrome in PiP); [onToggle]
  /// fires when the PiP window's play/pause action is tapped.
  ///
  /// The handlers are static, so they belong to whoever registered last. The
  /// returned token is that ownership: hand it to [unregister] on teardown. When
  /// one player replaces another (series auto-advance), the incoming screen
  /// registers before the outgoing one disposes, and an unconditional clear
  /// would wipe the new screen's handlers (ARGY-265).
  static Object register({
    void Function(bool inPip)? onChanged,
    void Function()? onToggle,
  }) {
    final token = Object();
    _owner = token;
    _onChanged = onChanged;
    _onToggle = onToggle;
    if (!_handlerInstalled && Platform.isAndroid) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_handle);
    }
    return token;
  }

  /// Clears the handlers only if [token] still owns them; a no-op once a later
  /// [register] has taken over.
  static void unregister(Object token) {
    if (!identical(_owner, token)) return;
    _owner = null;
    _onChanged = null;
    _onToggle = null;
  }

  static Object? _owner;

  @visibleForTesting
  static Future<void> debugHandle(MethodCall call) => _handle(call);

  static Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'pipChanged':
        _onChanged?.call(call.arguments == true);
      case 'pipAction':
        if (call.arguments == 'toggle') _onToggle?.call();
    }
  }
}
