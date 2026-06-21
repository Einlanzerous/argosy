import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/artwork.dart';
import '../../router/app_router.dart';
import '../../widgets/poster_card.dart';
import 'media_card.dart';

/// A [PosterCard] bound to a [MediaCard]: resolves the server's relative
/// artwork path to an absolute URL and, by default, navigates to the matching
/// detail route on tap. The single tile used by the grid, rails, and search.
class MediaPosterCard extends ConsumerWidget {
  const MediaPosterCard({
    super.key,
    required this.card,
    this.width = 132,
    this.onTap,
  });

  final MediaCard card;
  final double width;

  /// Overrides the default "open detail" navigation.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    return PosterCard(
      title: card.title,
      subtitle: card.subtitle,
      imageUrl: art(card.posterUrl),
      progress: card.progress,
      width: width,
      onTap: onTap ?? () => openDetail(context, card.kind, card.id),
    );
  }
}
