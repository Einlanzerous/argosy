import 'package:flutter/material.dart';

import '../../theme/argosy_colors.dart';
import '../../widgets/argosy_mark.dart';

/// Shown while the session bootstraps ([AuthStatus.unknown]). The router moves
/// off this screen automatically once auth resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArgosyMark(size: 104),
            const SizedBox(height: 20),
            Text('ARGOSY', style: _wordmark(context)),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle? _wordmark(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            letterSpacing: 6,
            fontWeight: FontWeight.w700,
            color: ArgosyColors.cream,
          );
}
