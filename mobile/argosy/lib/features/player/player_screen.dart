import 'package:flutter/material.dart';

import '../../theme/argosy_colors.dart';

/// Placeholder for the video player. The real playback experience (direct play
/// + HLS transcode, subtitles, cross-device resume) lands in ARGY-79; the
/// browse surfaces wire their Play / Resume entry points to this route now so
/// the navigation is in place.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.itemId, this.resume = false});

  final String itemId;
  final bool resume;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArgosyColors.ink,
      appBar: AppBar(
        backgroundColor: ArgosyColors.ink,
        iconTheme: const IconThemeData(color: ArgosyColors.cream),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_outline,
                  size: 64, color: ArgosyColors.accent),
              const SizedBox(height: 20),
              Text(
                resume ? 'Resuming playback…' : 'Playback',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              Text(
                'The player arrives in ARGY-79. This screen stands in so the '
                'browse surfaces can hand off to it.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
