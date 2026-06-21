import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/argosy_colors.dart';
import '../../widgets/argosy_mark.dart';
import 'auth_controller.dart';

/// The auth gate. A scaffold placeholder — a single "Connect" button stands in
/// for real server-pairing + profile selection, which arrives in ARGY-46.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(child: ArgosyMark(size: 84)),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome aboard',
                    textAlign: TextAlign.center,
                    style: text.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to your Argosy server to start streaming your library.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signIn(),
                    child: const Text('Connect'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Server pairing & profiles arrive next (ARGY-46).',
                    textAlign: TextAlign.center,
                    style: text.labelMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
