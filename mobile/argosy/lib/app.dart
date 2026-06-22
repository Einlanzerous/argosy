import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/beacon/beacon_providers.dart';
import 'router/app_router.dart';
import 'theme/argosy_theme.dart';

/// Root widget: wires the Argosy theme to the auth-gated [routerProvider].
class ArgosyApp extends ConsumerWidget {
  const ArgosyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hold the Beacon SSE stream open for the whole signed-in session so the
    // Continue-Watching row stays live with other devices (a no-op until
    // authenticated). Watched here, at the root, so it outlives tab/screen
    // navigation.
    ref.watch(beaconSyncProvider);

    return MaterialApp.router(
      title: 'Argosy',
      debugShowCheckedModeBanner: false,
      theme: buildArgosyTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
