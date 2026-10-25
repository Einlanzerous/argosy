import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../platform/device_capabilities.dart';

/// The `X-Argosy-Client` header name (ARGY-262).
const clientHeaderName = 'X-Argosy-Client';

/// Formats the client string the server logs and stores per device:
/// `argosy-android/0.32.0+78 (Pixel 9; Android 36)`.
///
/// [app] is `android`, `ios` or `tv` (the TV build is the same Android app).
/// Pure so the shape is testable without a platform channel.
String formatClientIdentity({
  required String app,
  required String version,
  String build = '',
  String? model,
  String? os,
}) {
  final v = build.isEmpty ? version : '$version+$build';
  final hw = [
    if (model != null && model.isNotEmpty) model,
    if (os != null && os.isNotEmpty) os,
  ].join('; ');
  return hw.isEmpty ? 'argosy-$app/$v' : 'argosy-$app/$v ($hw)';
}

/// Who this install says it is on every request. Resolved once by [load]
/// (before `runApp`, and again at the top of the download isolate, which has
/// its own copy of this static) and read synchronously after that, so the API
/// client's default headers and the HLS/segment header map can both use it.
class ClientIdentity {
  ClientIdentity._();

  static String _value = 'argosy-mobile/unknown';

  /// The header value. A safe placeholder until [load] completes — still
  /// identifies the request as mobile, which beats sending nothing.
  static String get value => _value;

  /// `{X-Argosy-Client: ...}`, ready to merge into any header map.
  static Map<String, String> get header => {clientHeaderName: _value};

  /// Resolves version/build and hardware. Never throws: a plugin that is not
  /// registered (a background isolate, a test) just leaves the placeholder
  /// rather than failing the app.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      String? model;
      String? os;
      var app = 'mobile';
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        model = a.model;
        os = 'Android ${a.version.sdkInt}';
        app = await DeviceCapabilities.isTelevision() ? 'tv' : 'android';
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        model = i.utsname.machine;
        os = 'iOS ${i.systemVersion}';
        app = 'ios';
      }
      _value = formatClientIdentity(
        app: app,
        version: info.version,
        build: info.buildNumber,
        model: model,
        os: os,
      );
    } catch (_) {
      // Keep whatever we had.
    }
  }

  /// For tests.
  static void debugSet(String value) => _value = value;
}
