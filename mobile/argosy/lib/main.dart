import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'platform/device_capabilities.dart';
import 'platform/device_type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the device type once up front so the root can synchronously pick the
  // TV (10-foot, D-pad) shell vs. the touch shell (ARGY-51).
  final isTv = await DeviceCapabilities.isTelevision();
  runApp(
    ProviderScope(
      overrides: [isTelevisionProvider.overrideWithValue(isTv)],
      child: const ArgosyApp(),
    ),
  );
}
