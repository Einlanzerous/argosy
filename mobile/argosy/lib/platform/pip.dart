import 'dart:io';

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

  /// Registers [callback], invoked with the current PiP mode whenever it changes
  /// (so the player can hide its overlay chrome in PiP). Pass null to clear.
  static void onChanged(void Function(bool inPip)? callback) {
    _onChanged = callback;
    if (callback != null && !_handlerInstalled && Platform.isAndroid) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_handle);
    }
  }

  static Future<void> _handle(MethodCall call) async {
    if (call.method == 'pipChanged') {
      _onChanged?.call(call.arguments == true);
    }
  }
}
