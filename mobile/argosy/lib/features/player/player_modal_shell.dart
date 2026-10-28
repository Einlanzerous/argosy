import 'package:flutter/material.dart';

import '../../theme/argosy_colors.dart';

/// The phone player's full-screen modal frame: a near-black scrim that reads
/// over any video frame, a back arrow top-left so the viewer can always leave,
/// and a centred column capped at 420 px. Shared by the resume prompt and the
/// playback-error overlay so the two look like one family.
class PlayerModalShell extends StatelessWidget {
  const PlayerModalShell({
    super.key,
    required this.onBack,
    required this.child,
  });

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xE6000000),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: ArgosyColors.cream),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
