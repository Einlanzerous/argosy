import 'package:flutter/material.dart';

import '../theme/argosy_tokens.dart';
import 'hatch_pattern.dart';

/// A 2:3 poster tile — artwork (or a hatch placeholder), title, and an
/// optional secondary line plus watch-progress bar. The building block of the
/// home rails and library grids.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.progress,
    this.width = 132,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;

  /// Watch progress in 0..1, or null for none.
  final double? progress;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.argosy;
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
              aspectRatio: 2 / 3,
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
                      if (imageUrl != null)
                        Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const HatchPlaceholder(),
                          loadingBuilder: (context, child, progress) =>
                              progress == null ? child : const HatchPlaceholder(),
                        )
                      else
                        const HatchPlaceholder(),
                      if (progress != null && progress! > 0)
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: tokens.line2,
                            valueColor:
                                AlwaysStoppedAnimation(tokens.progress),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
