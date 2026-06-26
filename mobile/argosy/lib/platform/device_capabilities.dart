import 'dart:io';

import 'package:flutter/services.dart';

/// Probes what the device's hardware can decode, so the client can advertise
/// its capability to the transcode endpoint (mirrors the web player's
/// `MediaSource.isTypeSupported` probe).
///
/// The one capability the server cares about today is **4K HEVC decode**: when
/// the client advertises it, the server remux-copies true-4K HEVC sources
/// untouched instead of re-encoding them down to H.264 1080p (ARGY-79).
class DeviceCapabilities {
  DeviceCapabilities._();

  static const _channel = MethodChannel('dev.dodson.argosy/capabilities');

  static bool? _hevc4k;
  static bool? _isTv;

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
}
