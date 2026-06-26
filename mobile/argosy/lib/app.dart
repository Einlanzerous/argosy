import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/beacon/beacon_providers.dart';
import 'platform/device_type.dart';
import 'router/app_router.dart';
import 'router/app_router_tv.dart';
import 'theme/argosy_theme.dart';
import 'theme/argosy_theme_tv.dart';

/// Root widget: wires the Argosy theme to the auth-gated router. On a TV the
/// 10-foot D-pad shell (theme + router) is used; everywhere else, the touch
/// shell (ARGY-51). Detection is resolved in `main()` and injected via
/// [isTelevisionProvider].
class ArgosyApp extends ConsumerWidget {
  const ArgosyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hold the Beacon SSE stream open for the whole signed-in session so the
    // Continue-Watching row stays live with other devices (a no-op until
    // authenticated). Watched here, at the root, so it outlives tab/screen
    // navigation.
    ref.watch(beaconSyncProvider);

    final isTv = ref.watch(isTelevisionProvider);

    return MaterialApp.router(
      title: 'Argosy',
      debugShowCheckedModeBanner: false,
      theme: isTv ? buildArgosyThemeTv() : buildArgosyTheme(),
      routerConfig: ref.watch(isTv ? routerTvProvider : routerProvider),
    );
  }
}
