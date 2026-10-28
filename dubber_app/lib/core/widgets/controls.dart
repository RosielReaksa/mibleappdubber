import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'app_widgets.dart';

/// White card row used across Projects and Account.
class ListTileCard extends StatelessWidget {
  const ListTileCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tokens.white,
      borderRadius: BorderRadius.circular(Tokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.radiusCard),
            border: Border.all(color: Tokens.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Two-option segmented control (Landscape / Portrait, Dubbed / Original).
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.background = Tokens.segmentBg,
    this.semanticLabel,
  });

  final List<({T value, String label, IconData? icon})> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color background;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
        ),
        child: Row(
          children: [
            for (final option in options)
              Expanded(
                child: _Segment(
                  label: option.label,
                  icon: option.icon,
                  selected: option.value == value,
                  onTap: () => onChanged(option.value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Tokens.ink : Tokens.muted;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: selected ? Tokens.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Tokens.clayButton : Tokens.muted,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Tokens.fontBody,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
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

/// Fully round chip used for voice choice and presets.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? Tokens.softClay : Tokens.white,
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            border: Border.all(
              color: selected ? Tokens.clayButton : Tokens.borderStrong,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 16, color: Tokens.clayButton),
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 16, color: Tokens.muted),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: Tokens.fontBody,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? Tokens.clayButton : Tokens.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled slider row with a percentage readout.
class MixSlider extends StatelessWidget {
  const MixSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.labelWidth,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (labelWidth != null)
              SizedBox(
                width: labelWidth,
                child: Text(label, style: AppText.label),
              )
            else
              Expanded(child: Text(label, style: AppText.label)),
            Text(
              '$value%',
              style: AppText.labelMuted.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: Tokens.clay,
            inactiveTrackColor: Tokens.border,
            thumbColor: Tokens.ink,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: const _ThinThumb(),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$value%',
            semanticFormatterCallback: (v) => '$label ${v.round()} percent',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _ThinThumb extends SliderComponentShape {
  const _ThinThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(8, 20);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 8, height: 20),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = Tokens.ink);
  }
}
