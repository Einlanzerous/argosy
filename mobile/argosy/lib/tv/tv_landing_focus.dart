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
class TvLandingFocus extends StatefulWidget {
  const TvLandingFocus({super.key, required this.child});

  final Widget child;

  /// Focuses [node] after the current frame, unless the viewer has parked focus
  /// somewhere of their own choosing.
  ///
  /// Call from the claiming widget's `initState`. Scheduling, the
  /// is-it-rendered check and the guard all live here so the three screens that
  /// use this can't drift apart on any of them.
  static void claimOnMount(BuildContext context, FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      // Nothing rendered the node — e.g. a series with nothing playable. Focus
      // stays where it is rather than being requested into the void.
      if (node.context == null) return;

      final scope = context.getInheritedWidgetOfExactType<_TvLandingFocusScope>();
      assert(
        scope != null,
        'TvLandingFocus.claimOnMount needs a TvLandingFocus ancestor. Without '
        'one this claims unconditionally and will steal focus from a viewer who '
        'moved during the load — wrap the screen body in TvLandingFocus.',
      );
      if (scope == null || scope.canClaim()) node.requestFocus();
    });
  }

  @override
  State<TvLandingFocus> createState() => _TvLandingFocusState();
}

class _TvLandingFocusState extends State<TvLandingFocus> {
  /// The first real node to hold focus — in practice the nav rail's active item,
  /// via its autofocus.
  ///
  /// Scope nodes are skipped. A route's scope (or the root scope) can be what
  /// holds focus for a frame before autofocus resolves, and recording *that* as
  /// the landing would make the rail's own autofocus read as "the viewer moved",
  /// disabling the claim for the life of the screen.
  FocusNode? _landed;

  void _onFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return;
    _landed ??= primary;
  }

  /// Whether the primary action may take focus right now.
  ///
  /// Evaluated at claim time rather than latched. A latch set by the claim
  /// itself would make this single-shot per screen: the content going away and
  /// coming back — an error panel and a Retry, which both detail screens and
  /// Home can reach through `onRetry` — would then land the remote back on the
  /// nav rail, which is the bug this exists to fix.
  bool _canClaim() {
    final primary = FocusManager.instance.primaryFocus;
    // Nothing real holds focus: either it was never taken, or whatever held it
    // has just been torn down. Claiming is the whole point in that case.
    if (primary == null || primary is FocusScopeNode) return true;
    if (primary.context == null) return true;
    // Otherwise only claim from the screen's own landing spot — anywhere else
    // is somewhere the viewer chose.
    return identical(primary, _landed);
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
    return _TvLandingFocusScope(canClaim: _canClaim, child: widget.child);
  }
}

class _TvLandingFocusScope extends InheritedWidget {
  const _TvLandingFocusScope({required this.canClaim, required super.child});

  final bool Function() canClaim;

  // Nothing rebuilds on this; descendants call through it imperatively.
  @override
  bool updateShouldNotify(_TvLandingFocusScope oldWidget) => false;
}
