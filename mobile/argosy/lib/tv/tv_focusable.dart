import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// The core 10-foot focus primitive (ARGY-51): wraps [child] so it's reachable
/// by D-pad, and paints the design's focus treatment when focused — a 3px brass
/// ring offset outside the content, a soft brass glow, and a slight scale-up.
///
/// The ring is drawn as a non-layout overlay (negative-inset [Positioned]) so
/// focusing never reflows siblings — it only grows visually. Activation fires
/// [onSelect] on D-pad center / Enter / Space (via [ActivateIntent]) and on tap
/// (handy on an emulator or with a mouse).
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onSelect,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = 14,
    this.scale = 1.06,
    this.focusOffset = 5,
    this.onFocusChange,
    this.ensureVisibleOnFocus = false,
    this.ensureVisibleAlignment = 0.12,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Corner radius of the *content*; the ring rounds to this + [focusOffset].
  final double borderRadius;

  /// How much the element grows when focused (design uses 1.05–1.12).
  final double scale;

  /// Gap between the content edge and the ring (the design's outline-offset).
  final double focusOffset;

  final ValueChanged<bool>? onFocusChange;

  /// When true, gaining focus scrolls every enclosing [Scrollable] so this
  /// element stays in view — the horizontal rail *and* the vertical page in one
  /// call (Flutter's [Scrollable.ensureVisible] walks all ancestors). Set on
  /// tiles inside the TV rails and the episode list so D-pad navigation keeps
  /// the focused item on screen with a leading inset.
  final bool ensureVisibleOnFocus;

  /// Where in the viewport the focused element lands (0 = leading edge, 0.5 =
  /// centered). A small value keeps a comfortable leading inset.
  final double ensureVisibleAlignment;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  /// Created when no [TvFocusable.focusNode] is supplied.
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  void _setFocused(bool v) {
    if (v == _focused) return;
    setState(() => _focused = v);
    widget.onFocusChange?.call(v);
    if (v && widget.ensureVisibleOnFocus) {
      // After the focus frame settles, scroll every enclosing scrollable so the
      // element is on screen (horizontal rail + vertical page in one call).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: widget.ensureVisibleAlignment,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = widget.focusOffset;
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: _setFocused,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (_focused)
                Positioned(
                  left: -off,
                  top: -off,
                  right: -off,
                  bottom: -off,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(widget.borderRadius + off),
                        border: Border.all(color: ArgosyColors.accent, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x29C99A4E), // brass glow, ~0.16
                            spreadRadius: 5,
                          ),
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 40,
                            offset: Offset(0, 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
