import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// The Dubber character: a clay figure with headphones at a mixing desk.
///
/// Draws the same shapes as the mockup SVG. All motion is disabled when the
/// platform asks for reduced motion ([MediaQuery.disableAnimations]).
class DubberCharacter extends StatefulWidget {
  const DubberCharacter({
    super.key,
    this.size = 300,
    this.mood = CharacterMood.happy,
  });

  final double size;
  final CharacterMood mood;

  @override
  State<DubberCharacter> createState() => _DubberCharacterState();
}

enum CharacterMood { happy, worried }

class _DubberCharacterState extends State<DubberCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: 'A little character wearing headphones mixing sound at a desk',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size * 220 / 300,
        child: reduceMotion
            ? CustomPaint(
                painter: _CharacterPainter(
                  t: const AlwaysStoppedAnimation(0),
                  mood: widget.mood,
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => CustomPaint(
                  painter: _CharacterPainter(
                    t: _controller,
                    mood: widget.mood,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  _CharacterPainter({required this.t, required this.mood});

  final Animation<double> t;
  final CharacterMood mood;

  static const _designW = 300.0;
  static const _designH = 220.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _designW, size.height / _designH);

    final time = t.value * 12; // seconds 0..12
    final bob = math.sin(time / 2 * math.pi) * 5;
    final blink = _blinkScale(time);

    final fill = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(150, 210), width: 220, height: 16),
      Paint()..color = Tokens.ink.withValues(alpha: 0.06),
    );

    // Floating sparks
    _spark(canvas, const Offset(58, 70), time, 3.0, 1.0);
    _spark(canvas, const Offset(244, 84), time, 3.0, 1.0);
    _spark(canvas, const Offset(262, 150), time, 3.0, 1.0);
    _spark(canvas, const Offset(150, 36), time * 2, 6.0, 1.4);

    // Sound waves
    stroke
      ..color = Tokens.clay
      ..strokeWidth = 3;
    final wave = 0.15 + 0.75 * ((math.sin(time * 2 * math.pi / 1.6) + 1) / 2);
    for (final side in [-1, 1]) {
      final cx = side == -1 ? 78.0 : 222.0;
      final dx = 10.0 * side;
      stroke.color = Tokens.clay.withValues(alpha: wave);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(cx + dx, 120),
          width: 20,
          height: 26,
        ),
        side == -1 ? math.pi * 0.65 : -math.pi * 0.35,
        side == -1 ? math.pi * 0.7 : -math.pi * 0.7,
        false,
        stroke,
      );
    }

    // Body + head
    final head = Rect.fromCenter(
      center: Offset(150, 120 + bob),
      width: 116,
      height: 104,
    );
    canvas.drawOval(head, fill..color = Tokens.clay);

    // Headphone band
    stroke
      ..color = Tokens.ink
      ..strokeWidth = 8;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(150, 112 + bob),
        width: 104,
        height: 96,
      ),
      math.pi,
      math.pi,
      false,
      stroke,
    );

    // Earcups
    fill.color = Tokens.ink;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(91, 106 + bob, 14, 28),
        const Radius.circular(7),
      ),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(195, 106 + bob, 14, 28),
        const Radius.circular(7),
      ),
      fill,
    );

    // Eyes (blink by squashing vertically)
    fill.color = Tokens.ink;
    for (final ex in [130.0, 170.0]) {
      canvas.save();
      canvas.translate(ex, 120 + bob);
      canvas.scale(1, blink);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 10, height: 14),
        fill,
      );
      canvas.restore();
    }

    // Cheeks
    fill.color = Tokens.softClay.withValues(alpha: 0.75);
    canvas.drawCircle(Offset(116, 136 + bob), 6, fill);
    canvas.drawCircle(Offset(184, 136 + bob), 6, fill);

    // Mouth: smile or worried
    stroke
      ..color = Tokens.ink
      ..strokeWidth = 3;
    if (mood == CharacterMood.happy) {
      final path = Path()
        ..moveTo(143, 134 + bob)
        ..quadraticBezierTo(150, 141 + bob, 157, 134 + bob);
      canvas.drawPath(path, stroke);
    } else {
      final path = Path()
        ..moveTo(143, 140 + bob)
        ..quadraticBezierTo(150, 133 + bob, 157, 140 + bob);
      canvas.drawPath(path, stroke);
    }

    // Desk
    final desk = RRect.fromRectAndRadius(
      const Rect.fromLTWH(40, 160, 220, 46),
      const Radius.circular(14),
    );
    canvas.drawRRect(desk, fill..color = Tokens.white);
    canvas.drawRRect(
      desk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.border,
    );

    // Slider tracks
    stroke
      ..color = Tokens.borderStrong
      ..strokeWidth = 4;
    for (final x in [85.0, 150.0, 215.0]) {
      canvas.drawLine(Offset(x, 170), Offset(x, 198), stroke);
    }

    // Knobs sliding
    fill.color = Tokens.clayButton;
    for (var i = 0; i < 3; i++) {
      final speed = [1.6, 2.2, 1.9][i];
      final phase = [0.0, -0.6, -1.0][i];
      final y = 168 + 8 * ((math.sin((time / speed + phase) * 2 * math.pi) + 1) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH([77.0, 142.0, 207.0][i], y, 16, 8),
          const Radius.circular(4),
        ),
        fill,
      );
    }

    // Hands tapping
    fill.color = Tokens.clay;
    for (var i = 0; i < 2; i++) {
      final speed = [1.6, 2.2][i];
      final phase = [0.0, -0.6][i];
      final y = 158 + 4 * ((math.sin((time / speed + phase) * 2 * math.pi) + 1) / 2);
      canvas.drawCircle(Offset([112.0, 188.0][i], y), 9, fill);
    }

    canvas.restore();
  }

  /// Blink every ~4 s: squash the eyes briefly.
  double _blinkScale(double time) {
    final cycle = time % 4;
    if (cycle > 3.68 && cycle < 3.84) {
      final p = (cycle - 3.68) / 0.16;
      return 1 - 0.9 * math.sin(p * math.pi);
    }
    return 1;
  }

  void _spark(Canvas canvas, Offset center, double time, double period, double scale) {
    final p = (time % period) / period;
    final opacity = p < 0.5 ? p * 2 : (1 - p) * 2;
    final dy = 8 - 22 * p;
    final s = scale * (0.6 + 0.4 * p);

    final paint = Paint()
      ..color = Tokens.clay.withValues(alpha: opacity.clamp(0, 1) * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy + dy);
    canvas.scale(s);
    canvas.drawLine(const Offset(0, -7), const Offset(0, 7), paint);
    canvas.drawLine(const Offset(-6, -3.5), const Offset(6, 3.5), paint);
    canvas.drawLine(const Offset(-6, 3.5), const Offset(6, -3.5), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CharacterPainter old) =>
      old.mood != mood || old.t != t;
}
