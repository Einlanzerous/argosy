import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Probes what the device's hardware can decode, so the client can advertise
/// its capability to the transcode endpoint (mirrors the web player's
/// `MediaSource.isTypeSupported` probe).
///
/// The capabilities the server cares about: **4K HEVC decode** (`hevc`), which
/// lets it remux-copy true-4K 8-bit HEVC instead of re-encoding to H.264 1080p
/// (ARGY-79); **hardware HEVC Main10 decode** (`hevcHardware`), which extends
/// the copy to 10-bit sources (ARGY-179, ARGY-275); and, for the TV, the
/// panel's **display mode height**, which the player sends as a ladder hint so
/// the server encodes one rung at the output resolution (ARGY-179).
class DeviceCapabilities {
  DeviceCapabilities._();

  static const _channel = MethodChannel('dev.dodson.argosy/capabilities');

  static bool? _hevc4k;
  static bool? _hevcHardware;
  static bool? _isTv;

  // `null` is a legitimate answer for the mode height (non-Android, channel
  // error), so "probed" is a separate flag rather than nullable-means-unprobed.
  static bool _displayProbed = false;
  static int? _displayModeHeight;

  /// Sentinel for [debugOverride]'s `displayModeHeight`, so a test can seed
  /// "probed, answer null" distinctly from "leave it alone".
  static const Object _unset = Object();

  /// Seeds the caches for tests: `Platform.isAndroid` is false under
  /// `flutter test`, so the channel is never reached there. Any parameter left
  /// out is untouched. Undo with [debugReset].
  @visibleForTesting
  static void debugOverride({
    bool? hevc4k,
    bool? hevcHardware,
    Object? displayModeHeight = _unset,
    bool? isTelevision,
  }) {
    if (hevc4k != null) _hevc4k = hevc4k;
    if (hevcHardware != null) _hevcHardware = hevcHardware;
    if (isTelevision != null) _isTv = isTelevision;
    if (!identical(displayModeHeight, _unset)) {
      _displayProbed = true;
      _displayModeHeight = displayModeHeight as int?;
    }
  }

  /// Clears every cache so the next read probes again (tests' `tearDown`).
  @visibleForTesting
  static void debugReset() {
    _hevc4k = null;
    _hevcHardware = null;
    _isTv = null;
    _displayProbed = false;
    _displayModeHeight = null;
  }

  /// Whether this is a TV / leanback device (Android TV, Google TV), which
  /// selects the 10-foot D-pad UI instead of the touch UI (ARGY-51). Cached
  /// after the first call. Non-Android platforms are never TV here.
  static Future<bool> isTelevision() async {
    if (_isTv != null) return _isTv!;
    if (!Platform.isAndroid) return _isTv = false;
    try {
      final tv = await _channel.invokeMethod<bool>('isTelevision');
      return _isTv = tv ?? false;
    } on PlatformException {
      return _isTv = false;
    } on MissingPluginException {
      return _isTv = false;
    }
  }

  /// Whether the device has an HEVC decoder that supports 3840×2160. Cached
  /// after the first call. Falls back to `false` (the safe, always-playable
  /// choice — the server transcodes to H.264 instead) if detection fails or the
  /// platform has no channel handler.
  ///
  /// iOS is reported as `true`: AVPlayer decodes 4K HEVC on every supported
  /// device, and the channel is Android-only for now.
  static Future<bool> supportsHevc4k() async {
    if (_hevc4k != null) return _hevc4k!;
    if (Platform.isIOS) return _hevc4k = true;
    if (!Platform.isAndroid) return _hevc4k = false;
    try {
      final ok = await _channel.invokeMethod<bool>('hevc4k');
      return _hevc4k = ok ?? false;
    } on PlatformException {
      return _hevc4k = false;
    } on MissingPluginException {
      return _hevc4k = false;
    }
  }

  /// Whether the device has a *hardware* HEVC Main10 decoder that supports
  /// 3840×2160 (ARGY-179 ruling 2). Sent as `hevcHardware`; when true the
  /// server copies 10-bit 4K HEVC instead of re-encoding it to 8-bit. Cached
  /// after the first call.
  ///
  /// iOS is `false`: there is no VideoToolbox query in the tree to assert
  /// hardware Main10 from, and `supportsHevc4k`'s iOS `true` is a hard-coded
  /// assumption, not a probe. A false answer only costs the re-encode that
  /// happens today; a wrong true routes 10-bit to a software decoder, which is
  /// the ARGY-150 stutter.
  static Future<bool> hevcHardware() async {
    if (_hevcHardware != null) return _hevcHardware!;
    if (!Platform.isAndroid) return _hevcHardware = false;
    try {
      final ok = await _channel.invokeMethod<bool>('hevcHardware');
      return _hevcHardware = ok ?? false;
    } on PlatformException {
      return _hevcHardware = false;
    } on MissingPluginException {
      return _hevcHardware = false;
    }
  }

  /// The display's active mode height in pixels (`Display.Mode`, via Media3),
  /// or `null` when it cannot be read or the platform has no channel handler.
  /// This is the panel's output mode, not the Flutter window: Android TV builds
  /// commonly run the UI at 1080p on a 4K panel. Cached after the first call,
  /// including a `null` answer.
  static Future<int?> displayModeHeight() async {
    if (_displayProbed) return _displayModeHeight;
    _displayProbed = true;
    if (!Platform.isAndroid) return _displayModeHeight = null;
    try {
      return _displayModeHeight = await _channel.invokeMethod<int>(
        'displayModeHeight',
      );
    } on PlatformException {
      return _displayModeHeight = null;
    } on MissingPluginException {
      return _displayModeHeight = null;
    }
  }
}
