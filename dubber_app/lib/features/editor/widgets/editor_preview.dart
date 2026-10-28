import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../projects/domain/models.dart';
import '../application/editor_controller.dart';

/// Light preview: a dark stage with overlays drawn as Flutter widgets.
/// It never re-encodes video; the server renders the final file.
///
/// The stage keeps the video's aspect ratio but is bounded by [maxHeight], so
/// a 9:16 portrait preview cannot push the tool panel and tool bar off screen.
class EditorPreview extends StatelessWidget {
  const EditorPreview({
    super.key,
    required this.state,
    required this.onMoveText,
    this.maxHeight = 340,
  });

  final EditorState state;
  final void Function({required double x, required double y}) onMoveText;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final isPortrait = state.format == VideoFormat.portrait;
    final ratio = isPortrait ? 9 / 16 : 16 / 9;

    return LayoutBuilder(
      builder: (context, outer) {
        // Fit the stage inside the available width *and* the height cap.
        final width = math.min(outer.maxWidth, maxHeight * ratio);

        return Center(
          child: SizedBox(
            width: width,
            height: width / ratio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusCard),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _stage(isPortrait, constraints),
                      if (state.filter != FilterName.none)
                        IgnorePointer(
                          child: Container(
                            color: _filterTint(state.filter, state.filterStrength),
                          ),
                        ),
                      ..._blurBoxes(constraints),
                      if (state.subtitlesOn)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 18,
                          child: _SubtitleSample(
                            style: state.subtitleStyle,
                            size: state.subtitleSize,
                          ),
                        ),
                      if (state.texts.isNotEmpty)
                        _draggableText(context, constraints),
                      if (state.logo.assetId != null) _logo(),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// The video stand-in, plus the fit simulation when formats differ.
  Widget _stage(bool isPortrait, BoxConstraints constraints) {
    final fill = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B8F9C), Color(0xFFD9A066), Color(0xFF8A5A44)],
        ),
      ),
    );

    if (!state.needsFit || state.fitMode == FitMode.fill) {
      return fill;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (state.fitMode == FitMode.blur)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: state.fitBlurStrength / 10,
                sigmaY: state.fitBlurStrength / 10,
              ),
              child: fill,
            ),
          )
        else
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
        Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: fill,
          ),
        ),
      ],
    );
  }

  Widget _draggableText(BuildContext context, BoxConstraints constraints) {
    final h = constraints.maxHeight;
    final text = state.texts.first;

    return Positioned(
      left: 0,
      right: 0,
      top: (text.y * h - 22).clamp(0.0, math.max(0.0, h - 44)),
      child: GestureDetector(
        onPanUpdate: (details) {
          onMoveText(
            x: text.x,
            y: (text.y * h + details.delta.dy) / h,
          );
        },
        child: Center(
          child: _TextSample(
            text: text.text,
            size: text.size,
            color: _hex(text.color),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    final logo = state.logo;
    final top = logo.position == LogoPosition.topLeft ||
        logo.position == LogoPosition.topRight;
    final left = logo.position == LogoPosition.topLeft ||
        logo.position == LogoPosition.bottomLeft;

    return Positioned(
      top: top ? 12 : null,
      bottom: top ? null : 12,
      left: left ? 12 : null,
      right: left ? null : 12,
      child: Opacity(
        opacity: logo.opacity / 100,
        child: Container(
          width: logo.size.toDouble(),
          height: logo.size.toDouble(),
          decoration: BoxDecoration(
            color: Tokens.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.image_outlined, color: Tokens.muted, size: 20),
        ),
      ),
    );
  }

  List<Widget> _blurBoxes(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final boxes = <Widget>[];

    for (final blur in state.blurs) {
      final thickness = blur.thickness / 100;
      final paint = Container(
        color: Tokens.ink.withValues(alpha: blur.strength / 140),
      );

      for (final side in blur.sides) {
        boxes.add(switch (side) {
          BlurSide.top => Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: h * thickness,
              child: paint,
            ),
          BlurSide.bottom => Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: h * thickness,
              child: paint,
            ),
          BlurSide.left => Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: w * thickness,
              child: paint,
            ),
          BlurSide.right => Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: w * thickness,
              child: paint,
            ),
        });
      }
    }
    return boxes;
  }

  Color _hex(String hex) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | value);
  }

  Color _filterTint(FilterName name, int strength) {
    final a = (strength / 100) * 0.35;
    return switch (name) {
      FilterName.none => Colors.transparent,
      FilterName.warm => const Color(0xFFD9A066).withValues(alpha: a),
      FilterName.cool => const Color(0xFF6B8F9C).withValues(alpha: a),
      FilterName.mono => const Color(0xFF808080).withValues(alpha: a),
      FilterName.vivid => Tokens.clay.withValues(alpha: a * 0.6),
      FilterName.soft => Colors.white.withValues(alpha: a * 0.7),
    };
  }
}

class _SubtitleSample extends StatelessWidget {
  const _SubtitleSample({required this.style, required this.size});

  final SubtitleStyle style;
  final int size;

  @override
  Widget build(BuildContext context) {
    final fontSize = (size / 3.2).clamp(10.0, 20.0);
    final base = TextStyle(
      fontFamily: Tokens.fontBody,
      fontSize: fontSize,
      color: Tokens.white,
      fontWeight:
          style == SubtitleStyle.bold ? FontWeight.w700 : FontWeight.w500,
      shadows: style == SubtitleStyle.box
          ? null
          : const [Shadow(color: Colors.black54, blurRadius: 3)],
    );

    return Center(
      child: Container(
        padding: style == SubtitleStyle.box
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
            : EdgeInsets.zero,
        decoration: style == SubtitleStyle.box
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Text(
          'Sample subtitle line',
          textAlign: TextAlign.center,
          style: base,
        ),
      ),
    );
  }
}

class _TextSample extends StatelessWidget {
  const _TextSample({
    required this.text,
    required this.size,
    required this.color,
  });

  final String text;
  final int size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Tokens.clay, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text.isEmpty ? 'Your text' : text,
        style: TextStyle(
          fontFamily: Tokens.fontHeading,
          fontWeight: FontWeight.w500,
          fontSize: (size / 2.6).clamp(12.0, 26.0),
          color: color,
        ),
      ),
    );
  }
}
