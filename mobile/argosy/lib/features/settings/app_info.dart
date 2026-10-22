import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Installed app version/build, loaded once from the platform. Shared by the
/// phone and TV settings screens so a household member's old install can be
/// identified from a screenshot (ARGY-249).
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
