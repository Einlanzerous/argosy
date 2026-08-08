import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/argosy_colors.dart';
import 'tv_focusable.dart';

/// Room reserved inside a rail's scroller for the focus ring of the tiles it
/// carries (ARGY-184).
///
/// One number for every rail rather than a per-rail [tvFocusClearance], so the
/// rails stay left-aligned with each other and the page can compensate with a
/// single offset. [TvRail] asserts it's enough for the tiles it was given.
const double kTvRailFocusInset = 22;

/// A titled horizontal rail for the TV home (ARGY-51 / `TVHome.dc.html`): a
/// brass tick + Archivo title (with an optional muted hint), over a horizontally
/// scrolling row of [children]. The tiles own their own focus + ensure-visible
/// (via [TvFocusable.ensureVisibleOnFocus]); this just lays out the header and
/// the scroller with the design's gaps and leading inset.
///
/// Wrap a column of these in a [TvRailGroup] so D-pad Up/Down steps one rail at
/// a time.
class TvRail extends StatefulWidget {
  const TvRail({
    super.key,
    required this.title,
    required this.children,
    required this.tileWidth,
    required this.tileHeight,
    this.hint,
    this.accent = false,
    this.gap = 28,
  });

  final String title;
  final List<Widget> children;

  /// Muted helper text trailing the title (e.g. "pick up on any deck").
  final String? hint;

  /// The first/focused rail draws a brass tick + brighter title.
  final bool accent;

  /// The box each tile is laid out in — the scroller sizes itself to
  /// [tileHeight] plus the focus-ring clearance above and below, and a tile is
  /// stretched to fill it. Rails vary (16:9 continue tiles vs. 2:3 posters), and
  /// the ring's reach scales with the tile, so both extents matter here.
  final double tileWidth;
  final double tileHeight;

  final double gap;

  @override
  State<TvRail> createState() => _TvRailState();
}

class _TvRailState extends State<TvRail> {
  /// A non-focusable parent for this rail's tiles, so [TvRailGroup] can tell
  /// which rail holds focus and which tiles are candidates in the next one.
  final FocusNode _node = FocusNode(
    debugLabel: 'tv-rail',
    canRequestFocus: false,
    skipTraversal: true,
  );

  TvRailGroupState? _group;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = TvRailGroup.of(context);
    if (identical(group, _group)) return;
    _group?.unregister(_node);
    _group = group;
    group?.register(_node);
  }

  @override
  void dispose() {
    _group?.unregister(_node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(
      kTvRailFocusInset >= tvFocusClearance(widget.tileWidth) &&
          kTvRailFocusInset >= tvFocusClearance(widget.tileHeight),
      'a ${widget.tileWidth}x${widget.tileHeight} tile needs more than '
      '${kTvRailFocusInset}px of clearance — its focus ring will be clipped by '
      'the rail (ARGY-184). Raise kTvRailFocusInset and re-check the page '
      'offsets that compensate for it.',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // Lines the title up with the tiles, which start one clearance in.
          padding: const EdgeInsets.only(left: kTvRailFocusInset),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 24,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: widget.accent
                      ? ArgosyColors.accent
                      : ArgosyColors.line3,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: 'Archivo',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: ArgosyColors.cream,
                ),
              ),
              if (widget.hint != null) ...[
                const SizedBox(width: 14),
                Text(
                  widget.hint!,
                  style: const TextStyle(
                    fontFamily: 'HankenGrotesk',
                    fontSize: 16,
                    color: ArgosyColors.mute,
                  ),
                ),
              ],
            ],
          ),
        ),
        // The design's 24px between the header and the first tile, less the
        // clearance the scroller now reserves above it.
        const SizedBox(height: 24 - kTvRailFocusInset),
        SizedBox(
          height: widget.tileHeight + 2 * kTvRailFocusInset,
          child: Focus(
            focusNode: _node,
            canRequestFocus: false,
            skipTraversal: true,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // The rail clips at its viewport, so the ring only survives if the
              // scroller carries the room for it (ARGY-184). Sideways it also
              // keeps a focused first tile off the edge, which is what the old
              // 4px inset was for.
              padding: const EdgeInsets.all(kTvRailFocusInset),
              itemCount: widget.children.length,
              separatorBuilder: (_, _) => SizedBox(width: widget.gap),
              itemBuilder: (_, i) => widget.children[i],
            ),
          ),
        ),
      ],
    );
  }
}

/// Makes D-pad Up/Down step one [TvRail] at a time (ARGY-184).
///
/// Flutter's directional traversal picks the nearest node that overlaps the
/// focused node's horizontal band, and only considers out-of-band nodes when
/// nothing is in it. Rails hold tiles at whatever x their own scroll offset puts
/// them, so a rail with few items often shares no band with the tile you're on —
/// and Up sails over it into the rail above. The shorter the rail, the more
/// reliably it's skipped, which is the opposite of what you want.
///
/// So the vertical hop is explicit: one rail per press, landing on whichever of
/// its tiles is nearest the horizontal centre you came from. Up from the first
/// rail and Down from the last are left alone, so the hero above and anything
/// below still work by ordinary traversal.
class TvRailGroup extends StatefulWidget {
  const TvRailGroup({super.key, required this.child});

  final Widget child;

  /// The enclosing group, or null when a rail is used outside one (it then just
  /// falls back to Flutter's traversal).
  static TvRailGroupState? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TvRailGroupScope>()?.state;

  @override
  State<TvRailGroup> createState() => TvRailGroupState();
}

class TvRailGroupState extends State<TvRailGroup> {
  /// Registered in mount order, which isn't screen order — a rail scrolled into
  /// view later mounts later. Sorted top-to-bottom at the moment of the press.
  final List<FocusNode> _rails = [];

  void register(FocusNode rail) {
    if (!_rails.contains(rail)) _rails.add(rail);
  }

  void unregister(FocusNode rail) => _rails.remove(rail);

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    // Down and repeat both move; ignoring repeats would hand a held D-pad back
    // to the traversal this exists to replace.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final int step;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      step = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      step = 1;
    } else {
      return KeyEventResult.ignored;
    }

    final from = FocusManager.instance.primaryFocus;
    if (from == null) return KeyEventResult.ignored;

    final rails = [
      for (final rail in _rails)
        if (rail.context != null) rail,
    ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));

    final at = rails.indexWhere((rail) => rail.descendants.contains(from));
    // Focus is on the hero, or somewhere else outside the rails — theirs to
    // resolve, not ours.
    if (at < 0) return KeyEventResult.ignored;
    final to = at + step;
    if (to < 0 || to >= rails.length) return KeyEventResult.ignored;

    final target = _nearest(rails[to], from.rect.center.dx);
    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }

  /// The tile in [rail] whose centre is closest to [x]. Only built tiles are
  /// candidates: a rail scrolled far along has the rest unbuilt, and they're
  /// off screen anyway.
  FocusNode? _nearest(FocusNode rail, double x) {
    FocusNode? best;
    var bestDistance = double.infinity;
    for (final node in rail.traversalDescendants) {
      if (node.context == null) continue;
      final distance = (node.rect.center.dx - x).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = node;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return _TvRailGroupScope(
      state: this,
      // A plain interceptor, not a FocusScope: it must never take focus itself,
      // only see the keys that reach it from the focused tile.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: widget.child,
      ),
    );
  }
}

class _TvRailGroupScope extends InheritedWidget {
  const _TvRailGroupScope({required this.state, required super.child});

  final TvRailGroupState state;

  // Rails read this once to register; nothing rebuilds on it.
  @override
  bool updateShouldNotify(_TvRailGroupScope oldWidget) => false;
}
