import 'package:flutter/widgets.dart';

/// Lets a TV screen's primary action claim focus when it appears, without
/// stealing it from a viewer who has already moved (ARGY-173).
///
/// TV screens hand first-frame focus to the nav rail: it exists before the async
/// content does, which is what stops the route's modal scope self-focusing and
/// killing D-pad traversal. The cost is that focus stays on a nav icon for the
/// screen you're already on, so the first SELECT does nothing and reaching
/// Resume takes two presses. The fix is for the primary action to take focus
/// once it mounts.
///
/// The catch is the gap in between. Detail and home providers wait on several
/// API calls, and the rail is fully focusable throughout — so a viewer can be
/// two presses down the rail when the content lands. Claiming focus at that
/// moment moves the remote off what they aimed at, onto a button that starts
/// playback. Worse than the problem being solved.
///
/// So this records where focus first landed and whether it has moved since;
/// [maybeClaim] is a no-op once it has.
///
/// Movement is tracked by listening to [FocusManager] rather than snapshotting
/// the landing node in a post-frame callback. The focus manager applies
/// autofocus in its *own* post-frame pass, which can run after a widget's, so a
/// snapshot taken there comes back null — and a null landing reads as "nothing
/// to protect", silently disabling the guard.
class TvLandingFocus extends StatefulWidget {
  const TvLandingFocus({super.key, required this.child});

  final Widget child;

  /// Focuses [node] unless the viewer has already moved focus since entry.
  ///
  /// Call from a descendant's `initState` inside a post-frame callback — the
  /// node isn't attached to an element until its subtree has been laid out.
  /// With no [TvLandingFocus] ancestor this focuses unconditionally, matching
  /// the behaviour of a screen that never had a landing to protect.
  static void maybeClaim(BuildContext context, FocusNode node) {
    final scope = context.getInheritedWidgetOfExactType<_TvLandingFocusScope>();
    if (scope == null || scope.untouched()) node.requestFocus();
  }

  @override
  State<TvLandingFocus> createState() => _TvLandingFocusState();
}

class _TvLandingFocusState extends State<TvLandingFocus> {
  /// The first node to actually hold focus — in practice the nav rail's active
  /// item, via its autofocus.
  FocusNode? _landed;
  bool _moved = false;

  void _onFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    if (_landed == null) {
      _landed = primary;
    } else if (primary != _landed) {
      _moved = true;
    }
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // untouched is read at claim time, not build time, so it reflects the moment
    // the claim would happen rather than the last rebuild.
    return _TvLandingFocusScope(untouched: () => !_moved, child: widget.child);
  }
}

class _TvLandingFocusScope extends InheritedWidget {
  const _TvLandingFocusScope({required this.untouched, required super.child});

  final bool Function() untouched;

  // Nothing rebuilds on this; descendants call through it imperatively.
  @override
  bool updateShouldNotify(_TvLandingFocusScope oldWidget) => false;
}
