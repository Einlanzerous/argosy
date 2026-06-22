import 'package:flutter/material.dart';

import 'argosy_colors.dart';
import 'argosy_tokens.dart';

/// Shared action-button styles so primary (brass) and secondary (ghost) actions
/// read as one family wherever they appear — detail screens, the Bridge hero,
/// etc. Both are `FilledButton`s, so they share the theme's rectangular shape
/// and only differ in fill/border; pass [minimumSize] to shrink them in tighter
/// surfaces (the hero uses a smaller height than the detail action row).

/// Default fixed height for detail-screen action buttons, so the brass and
/// ghost variants are always the same size regardless of icon/label. (Width
/// still flexes with the label, like the web row.)
const Size kActionButtonSize = Size(0, 52);

/// The primary action style (Play / Resume) — brass fill from the theme.
ButtonStyle brassButtonStyle(BuildContext context, {Size? minimumSize}) =>
    FilledButton.styleFrom(minimumSize: minimumSize ?? kActionButtonSize);

/// The "ghost" secondary action style (Details, Start over, Add to Vault) — same
/// shape + size as the brass button, but a subtle dark fill, hairline border,
/// and cream label so it reads as secondary without collapsing into the small
/// dashed "+ Label" pill. Mirrors the web's `.ghost` / `.trigger`.
ButtonStyle ghostButtonStyle(BuildContext context, {Size? minimumSize}) =>
    FilledButton.styleFrom(
      minimumSize: minimumSize ?? kActionButtonSize,
      backgroundColor: const Color(0x66141413),
      foregroundColor: ArgosyColors.cream,
      side: BorderSide(color: context.argosy.line2),
    );
