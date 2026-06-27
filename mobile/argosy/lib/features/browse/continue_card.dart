import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../theme/argosy_colors.dart';
import '../../theme/argosy_tokens.dart';
import '../../widgets/device_pill.dart';
import '../../widgets/hatch_pattern.dart';
import '../home/home_providers.dart';

/// A wide 16:9 "Continue Watching" tile — backdrop artwork with the title/sub
/// overlaid, a watch-progress bar across the bottom edge, and a remaining-time
/// footer. Tapping resumes the item directly.
class ContinueCard extends ConsumerWidget {
  const ContinueCard({
    super.key,
    required this.entry,
    this.width = 230,
    this.onTap,
  });

  final ContinueEntry entry;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.argosy;
    final art = ref.watch(artworkResolverProvider);
    final bg = art(entry.backdropUrl ?? entry.posterUrl);
    final radius = BorderRadius.circular(tokens.radiusLg);

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: tokens.line),
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bg != null)
                        Image.network(
                          bg,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const HatchPlaceholder(),
                          loadingBuilder: (context, child, p) =>
                              p == null ? child : const HatchPlaceholder(),
                        )
                      else
                        const HatchPlaceholder(),
                      // Legibility scrim under the overlaid text.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xD9000000)],
                            stops: [0.42, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (entry.subtitle != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                entry.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (entry.deviceLabel != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: DevicePill(label: entry.deviceLabel!),
                        ),
                      if (entry.progress > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: entry.progress.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: tokens.line2,
                            valueColor: AlwaysStoppedAnimation(tokens.progress),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (entry.remainingLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                entry.remainingLabel!,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: ArgosyColors.mute),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
