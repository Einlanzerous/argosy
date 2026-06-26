import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';
import 'tv_focusable.dart';

/// An in-app, D-pad-driven on-screen keyboard (ARGY-51). The system/leanback
/// IME is unusable from Flutter on a TV — focus can't move into it with the
/// remote — so TV text entry uses this instead: every key is a [TvFocusable],
/// so the remote navigates and selects keys like any other focusable widget,
/// and nothing ever depends on the platform keyboard.
///
/// Lowercase letters + digits + the handful of URL/email symbols cover server
/// addresses and credentials; a Space/Backspace/Clear control row sits at the
/// bottom.
class TvOnScreenKeyboard extends StatelessWidget {
  const TvOnScreenKeyboard({
    super.key,
    required this.onChar,
    required this.onBackspace,
    required this.onClear,
  });

  /// Append a single character to the active field.
  final ValueChanged<String> onChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const _rows = <String>[
    '1234567890',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
    '.:/-_@',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final ch in row.split(''))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: _Key(label: ch, onSelect: () => onChar(ch)),
                  ),
              ],
            ),
          ),
        // Control row.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _Key(
                label: 'Space',
                width: 220,
                onSelect: () => onChar(' '),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _Key(label: 'Delete', width: 150, onSelect: onBackspace),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _Key(label: 'Clear', width: 120, onSelect: onClear),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onSelect, this.width = 64});

  final String label;
  final VoidCallback onSelect;
  final double width;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 12,
      scale: 1.12,
      focusOffset: 4,
      onSelect: widget.onSelect,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        width: widget.width,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Focused key fills brass (design); otherwise a dark panel key.
          color: _focused ? ArgosyColors.accent : ArgosyColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _focused ? Colors.transparent : ArgosyColors.line,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontFamily: widget.label.length == 1 ? 'Archivo' : 'HankenGrotesk',
            fontSize: widget.label.length == 1 ? 26 : 18,
            fontWeight: FontWeight.w600,
            color: _focused ? ArgosyColors.ink : ArgosyColors.cream,
          ),
        ),
      ),
    );
  }
}
