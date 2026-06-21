import 'package:flutter/material.dart';

import '../theme/argosy_colors.dart';

/// The diagonal-hatch texture the design lays over poster/backdrop
/// placeholders — a port of the web's `.arg-hatch`
/// (`repeating-linear-gradient(135deg, rgba(234,234,229,.03) 0 2px, transparent 2px 9px)`).
class HatchPattern extends StatelessWidget {
  const HatchPattern({super.key, this.color, this.spacing = 9, this.stroke = 2});

  final Color? color;
  final double spacing;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _HatchPainter(
        color: color ?? ArgosyColors.cream.withValues(alpha: 0.03),
        spacing: spacing,
        stroke: stroke,
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({
    required this.color,
    required this.spacing,
    required this.stroke,
  });

  final Color color;
  final double spacing;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke;
    // 135° lines: sweep the offset across the full diagonal extent so the
    // pattern covers every corner regardless of aspect ratio.
    final extent = size.width + size.height;
    for (double d = 0; d <= extent; d += spacing) {
      canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.color != color || old.spacing != spacing || old.stroke != stroke;
}

/// Convenience: a hatch-filled rounded rectangle, the standard "no artwork yet"
/// placeholder used by [PosterCard] and friends.
class HatchPlaceholder extends StatelessWidget {
  const HatchPlaceholder({super.key, this.borderRadius, this.child});

  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: ColoredBox(
        color: ArgosyColors.panel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const HatchPattern(),
            Center(
              child: Icon(
                Icons.movie_outlined,
                color: ArgosyColors.cream.withValues(alpha: 0.10),
                size: 34,
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}
