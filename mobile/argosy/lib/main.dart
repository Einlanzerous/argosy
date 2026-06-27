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
