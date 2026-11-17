import 'package:flutter/widgets.dart';

/// The one width at which the phone app switches to its "expanded" layouts: a
/// left nav rail instead of the bottom bar, and two-pane / wider grids on
/// Bridge, Manifest and Series (ARGY-308).
///
/// 600dp is Material's compact/medium window-size-class boundary: a foldable's
/// inner screen (and a phone held sideways) crosses it, and every regular
/// portrait phone stays below it. Decide layout from this, never from a literal
/// width in a screen.
const double kExpandedWidth = 600;

/// True when the window is wide enough for the expanded layouts.
bool isExpandedWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kExpandedWidth;
