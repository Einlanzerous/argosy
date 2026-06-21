import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/argosy_theme.dart';

/// Root widget: wires the Argosy theme to the auth-gated [routerProvider].
class ArgosyApp extends ConsumerWidget {
  const ArgosyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Argosy',
      debugShowCheckedModeBanner: false,
      theme: buildArgosyTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
