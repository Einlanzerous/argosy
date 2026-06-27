import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/artwork.dart';
import '../theme/argosy_colors.dart';
import '../widgets/hatch_pattern.dart';

/// The 10-foot detail backdrop (ARGY-51): a full-bleed cover image behind the
/// left-to-right + bottom-up scrims, with the screen's [child] content laid out
/// over it. This fills the content region *beside* the nav rail — the TV detail
/// screens render the persistent rail themselves (outside their AsyncView) so it
/// holds focus while this content loads in.
class TvBackdrop extends ConsumerWidget {
  const TvBackdrop({
    super.key,
    required this.child,
    this.backdropUrl,
    this.posterUrl,
  });

  final Widget child;
  final String? backdropUrl;
  final String? posterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artworkResolverProvider);
    final img = art(backdropUrl ?? posterUrl);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null)
          Image.network(
            img,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const HatchPlaceholder(),
          )
        else
          const HatchPlaceholder(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF5141413), Color(0xA8141413), Color(0x0D141413)],
              stops: [0, 0.44, 0.82],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [ArgosyColors.bg, Color(0x4D171717), Color(0x00171717)],
              stops: [0.06, 0.46, 0.74],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
