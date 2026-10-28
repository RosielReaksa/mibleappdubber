import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import 'auth_page.dart';

/// The Dubber wordmark: equalizer glyph + serif name.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.fontSize = 30});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomPaint(
          size: const Size(32, 32),
          painter: _EqualizerPainter(),
        ),
        const SizedBox(width: 10),
        Text('Dubber', style: AppText.display(fontSize)),
      ],
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.clay
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Five vertical bars of different heights, as in the mockup logo.
    final heights = [8.0, 16.0, 26.0, 18.0, 10.0];
    final sx = size.width / 32;
    final sy = size.height / 32;
    for (var i = 0; i < heights.length; i++) {
      final x = (5 + i * 5) * sx;
      final h = heights[i] * sy;
      canvas.drawLine(
        Offset(x, (16 * sy) - h / 2),
        Offset(x, (16 * sy) + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
