import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/status_chip.dart';
import '../../library/widgets/library_widgets.dart';
import '../../library/application/library_controller.dart';
import '../../library/domain/library_models.dart';
import '../../library/sections/logos_section.dart';
import '../../library/sections/styles_section.dart';
import '../../library/widgets/library_widgets.dart';
import '../../projects/domain/models.dart';
import '../application/editor_controller.dart';

/// The panel below the preview for whichever tool is selected.
class ToolPanel extends StatelessWidget {
  const ToolPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: switch (state.tool) {
        EditorTool.text => _TextTool(state: state, controller: controller),
        EditorTool.logo => _LogoTool(state: state, controller: controller),
        EditorTool.subtitles => _SubtitlesTool(state: state, controller: controller),
        EditorTool.trim => _TrimTool(state: state, controller: controller),
        EditorTool.audio => _AudioTool(state: state, controller: controller),
        EditorTool.blur => _BlurTool(state: state, controller: controller),
        EditorTool.fit => _FitTool(state: state, controller: controller),
        EditorTool.filters => _FiltersTool(state: state, controller: controller),
      },
    );
  }
}

// ── Text ──────────────────────────────────────────────────────────────────

class _TextTool extends ConsumerStatefulWidget {
  const _TextTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  ConsumerState<_TextTool> createState() => _TextToolState();
}

class _TextToolState extends ConsumerState<_TextTool> {
  late final _text = TextEditingController(
    text: widget.state.texts.isEmpty ? '' : widget.state.texts.first.text,
  );

  static const _colors = ['#FFFFFF', '#141413', '#D97757', '#F6E7C6'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  TextOverlay get _current =>
      widget.state.texts.isEmpty ? const TextOverlay() : widget.state.texts.first;

  @override
  Widget build(BuildContext context) {
    final current = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: 'Text',
          hint: 'Type your text',
          controller: _text,
          onChanged: (v) => widget.controller.setText(current.copyWith(text: v)),
        ),
        const SizedBox(height: 12),
        MixSlider(
          label: 'Size',
          value: current.size,
          onChanged: (v) =>
              widget.controller.setText(current.copyWith(size: v)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Color', style: AppText.label),
            const SizedBox(width: 16),
            for (final hex in _colors)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _ColorDot(
                  hex: hex,
                  selected: current.color == hex,
                  onTap: () => widget.controller.setText(
                    current.copyWith(color: hex),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: SecondaryButton(label: 'Apply saved style', onPressed: () => showApplyStyleSheet(context, ref, tool: EditorTool.text, onApply: (style) => widget.controller.setText(current.copyWith(size: style.size, color: style.color))))),
          TextButton(onPressed: () async {
            final name = await askStyleName(context, initial: '');
            if (name == null || !mounted) return;
            final item = SavedStyle(id: 'style_${DateTime.now().microsecondsSinceEpoch}', name: name, kind: StyleKind.text, size: current.size, color: current.color);
            final result = await ref.read(styleLibraryProvider.notifier).create(item);
            if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style saved'));
          }, child: const Text('Save as style')),
        ]),
        const SizedBox(height: 12),
        Text(
          'Drag the text on the video to move it.',
          style: AppText.caption,
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0xFFFFFF;
    return Semantics(
      label: 'Color $hex',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Color(0xFF000000 | value),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Tokens.clay : Tokens.borderStrong,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Logo ──────────────────────────────────────────────────────────────────

class _LogoTool extends ConsumerWidget {
  const _LogoTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = state.logo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Choose from Library',
                icon: Icons.collections_bookmark_outlined,
                onPressed: () => showLogoPickerSheet(
                  context,
                  onPick: (saved) =>
                      controller.setLogo(logo.copyWith(assetId: saved.id)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SecondaryButton(
                label: logo.assetId == null ? 'Upload new' : 'Replace',
                icon: Icons.upload_outlined,
                onPressed: () {
                  // TODO(server): POST /assets/logos multipart. Until the
                  // endpoint exists the overlay uses a placeholder id so the
                  // position, size and opacity can still be set.
                  controller.setLogo(
                    logo.copyWith(assetId: logo.assetId ?? 'local_logo'),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MixSlider(
          label: 'Size',
          value: logo.size,
          onChanged: (v) => controller.setLogo(logo.copyWith(size: v)),
        ),
        MixSlider(
          label: 'Opacity',
          value: logo.opacity,
          onChanged: (v) => controller.setLogo(logo.copyWith(opacity: v)),
        ),
        const SizedBox(height: 8),
        Text('Corner', style: AppText.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final position in LogoPosition.values)
              AppChip(
                label: _positionLabel(position),
                selected: logo.position == position,
                onTap: () => controller.setLogo(logo.copyWith(position: position)),
              ),
          ],
        ),
      ],
    );
  }

  String _positionLabel(LogoPosition p) => switch (p) {
        LogoPosition.topLeft => 'Top left',
        LogoPosition.topRight => 'Top right',
        LogoPosition.bottomLeft => 'Bottom left',
        LogoPosition.bottomRight => 'Bottom right',
      };
}

// ── Subtitles ─────────────────────────────────────────────────────────────

class _SubtitlesTool extends ConsumerStatefulWidget {
  const _SubtitlesTool({required this.state, required this.controller});
  final EditorState state;
  final EditorController controller;
  @override
  ConsumerState<_SubtitlesTool> createState() => _SubtitlesToolState();
}

class _SubtitlesToolState extends ConsumerState<_SubtitlesTool> {
  EditorState get state => widget.state;
  EditorController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Show subtitles', style: AppText.label)),
            Switch(
              value: state.subtitlesOn,
              onChanged: (v) => controller.setSubtitles(show: v),
              activeThumbColor: Tokens.white,
              activeTrackColor: Tokens.clayButton,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Style', style: AppText.label),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final style in SubtitleStyle.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppChip(
                  label: _styleLabel(style),
                  selected: state.subtitleStyle == style,
                  onTap: () => controller.setSubtitles(style: style),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        MixSlider(
          label: 'Size',
          value: state.subtitleSize,
          onChanged: (v) => controller.setSubtitles(size: v),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: SecondaryButton(label: 'Apply saved style', onPressed: () => showApplyStyleSheet(context, ref, tool: EditorTool.subtitles, onApply: (style) => controller.setSubtitles(style: subtitleStyleFor(style), size: style.size)))),
          TextButton(onPressed: () async {
            final name = await askStyleName(context, initial: '');
            if (name == null || !mounted) return;
            final item = SavedStyle(id: 'style_${DateTime.now().microsecondsSinceEpoch}', name: name, kind: StyleKind.subtitle, size: state.subtitleSize, subtitleStyle: state.subtitleStyle);
            final result = await ref.read(styleLibraryProvider.notifier).create(item);
            if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style saved'));
          }, child: const Text('Save as style')),
        ]),
      ],
    );
  }

  String _styleLabel(SubtitleStyle s) => switch (s) {
        SubtitleStyle.classic => 'Classic',
        SubtitleStyle.bold => 'Bold',
        SubtitleStyle.box => 'Box',
      };
}

// ── Trim ──────────────────────────────────────────────────────────────────

class _TrimTool extends StatelessWidget {
  const _TrimTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set where the video starts and ends.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        RangeSlider(
          values: RangeValues(state.trimStart, state.trimEnd),
          min: 0,
          max: 90,
          divisions: 180,
          activeColor: Tokens.clay,
          inactiveColor: Tokens.border,
          labels: RangeLabels(
            _fmt(state.trimStart),
            _fmt(state.trimEnd),
          ),
          onChanged: (v) => controller.setTrim(start: v.start, end: v.end),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Start ${_fmt(state.trimStart)}', style: AppText.labelMuted),
            Text('End ${_fmt(state.trimEnd)}', style: AppText.labelMuted),
          ],
        ),
      ],
    );
  }

  String _fmt(double s) {
    final total = s.round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }
}

// ── Audio ─────────────────────────────────────────────────────────────────

class _AudioTool extends StatelessWidget {
  const _AudioTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final mix = state.mix;
    final preset = mix.presetName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Changing the mix never costs credits.',
          style: AppText.caption,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Preset(
                label: 'Replace',
                selected: preset == 'replace',
                onTap: () => controller.setMix(AudioMix.replaceVoice),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Preset(
                label: 'Voice-over',
                selected: preset == 'voiceOver',
                onTap: () => controller.setMix(AudioMix.voiceOver),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Preset(
                label: 'Keep original',
                selected: preset == 'keepOriginal',
                onTap: () => controller.setMix(AudioMix.keepOriginal),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        MixSlider(
          label: 'Dubbed voice',
          value: mix.dubbedVoice,
          onChanged: (v) => controller.setMix(mix.copyWith(dubbedVoice: v)),
        ),
        MixSlider(
          label: 'Original voice',
          value: mix.originalVoice,
          onChanged: (v) => controller.setMix(mix.copyWith(originalVoice: v)),
        ),
        MixSlider(
          label: 'Background music',
          value: mix.music,
          onChanged: (v) => controller.setMix(mix.copyWith(music: v)),
        ),
      ],
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? Tokens.softClay : Tokens.white,
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            border: Border.all(
              color: selected ? Tokens.clay : Tokens.borderStrong,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Tokens.fontBody,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Tokens.clayDeep : Tokens.bodyOnChip,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Blur ──────────────────────────────────────────────────────────────────

class _BlurTool extends StatelessWidget {
  const _BlurTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  BlurOverlay get _current =>
      state.blurs.isEmpty ? const BlurOverlay() : state.blurs.first;

  @override
  Widget build(BuildContext context) {
    final blur = _current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Where', style: AppText.label),
            const SizedBox(width: 8),
            Text('Tap more than one', style: AppText.caption),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final side in BlurSide.values)
              AppChip(
                label: _sideLabel(side),
                selected: blur.sides.contains(side),
                onTap: () {
                  final sides = {...blur.sides};
                  sides.contains(side) ? sides.remove(side) : sides.add(side);
                  controller.setBlur(blur.copyWith(sides: sides));
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        MixSlider(
          label: 'Thickness',
          value: blur.thickness,
          onChanged: (v) => controller.setBlur(blur.copyWith(thickness: v)),
        ),
        MixSlider(
          label: 'Strength',
          value: blur.strength,
          onChanged: (v) => controller.setBlur(blur.copyWith(strength: v)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final style in BlurStyle.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppChip(
                  label: style == BlurStyle.blur ? 'Blur' : 'Pixelate',
                  selected: blur.style == style,
                  onTap: () => controller.setBlur(blur.copyWith(style: style)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SecondaryButton(label: '+ Add blur', onPressed: controller.addBlur),
      ],
    );
  }

  String _sideLabel(BlurSide s) => switch (s) {
        BlurSide.top => 'Top',
        BlurSide.bottom => 'Bottom',
        BlurSide.left => 'Left',
        BlurSide.right => 'Right',
      };
}

// ── Fit ───────────────────────────────────────────────────────────────────

class _FitTool extends StatelessWidget {
  const _FitTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.needsFit
              ? 'Your video is ${_name(state.sourceFormat)}. Choose how it fills ${_name(state.format)}.'
              : 'Your video already matches the format. Fit does not change anything.',
          style: AppText.caption.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 12),
        _FitOption(
          title: 'Blurred background',
          subtitle: 'Video in the middle, soft blur around it',
          selected: state.fitMode == FitMode.blur,
          preview: _FitPreview.blur,
          onTap: () => controller.setFit(mode: FitMode.blur),
        ),
        const SizedBox(height: 8),
        _FitOption(
          title: 'Black bars',
          subtitle: 'Video in the middle, plain bars',
          selected: state.fitMode == FitMode.bars,
          preview: _FitPreview.bars,
          onTap: () => controller.setFit(mode: FitMode.bars),
        ),
        const SizedBox(height: 8),
        _FitOption(
          title: 'Fill screen',
          subtitle: 'Crops the sides to fill',
          selected: state.fitMode == FitMode.fill,
          preview: _FitPreview.fill,
          onTap: () => controller.setFit(mode: FitMode.fill),
        ),
        if (state.fitMode == FitMode.blur) ...[
          const SizedBox(height: 12),
          MixSlider(
            label: 'Blur strength',
            value: state.fitBlurStrength,
            onChanged: (v) => controller.setFit(blurStrength: v),
          ),
        ],
      ],
    );
  }

  String _name(VideoFormat f) =>
      f == VideoFormat.portrait ? 'Portrait' : 'Landscape';
}

enum _FitPreview { blur, bars, fill }

class _FitOption extends StatelessWidget {
  const _FitOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final _FitPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: selected ? Tokens.softClay : Tokens.white,
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
            border: Border.all(
              color: selected ? Tokens.clayButton : Tokens.borderStrong,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              _MiniPreview(mode: preview),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.label.copyWith(fontSize: 15)),
                    Text(subtitle, style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.mode});

  final _FitPreview mode;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      color: Tokens.clay,
    );

    return Container(
      width: 36,
      height: 48,
      decoration: BoxDecoration(
        color: mode == _FitPreview.bars ? Colors.black : const Color(0xFFB8826A),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (mode) {
        _FitPreview.blur => Center(
            child: Container(
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: Tokens.clay,
            ),
          ),
        _FitPreview.bars => Center(
            child: Container(
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              color: Tokens.clay,
            ),
          ),
        _FitPreview.fill => content,
      },
    );
  }
}

// ── Filters ───────────────────────────────────────────────────────────────

class _FiltersTool extends StatelessWidget {
  const _FiltersTool({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  static const _swatches = {
    FilterName.none: Color(0xFFD9A066),
    FilterName.warm: Color(0xFFE0A76A),
    FilterName.cool: Color(0xFF6B8F9C),
    FilterName.mono: Color(0xFF9A9A9A),
    FilterName.vivid: Color(0xFFE07A4A),
    FilterName.soft: Color(0xFFE3CDBA),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filter', style: AppText.label),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: FilterName.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final name = FilterName.values[i];
              final selected = state.filter == name;
              return Semantics(
                selected: selected,
                button: true,
                label: _label(name),
                child: GestureDetector(
                  onTap: () => controller.setFilter(name: name),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: _swatches[name],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? Tokens.clayButton
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _label(name),
                          style: AppText.caption.copyWith(
                            fontSize: 13,
                            color: selected ? Tokens.clayButton : Tokens.ink,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        MixSlider(
          label: 'Strength',
          value: state.filterStrength,
          onChanged: (v) => controller.setFilter(strength: v),
        ),
        Text(
          'Filters change colors only. Text and logos keep their colors.',
          style: AppText.caption,
        ),
      ],
    );
  }

  String _label(FilterName name) => switch (name) {
        FilterName.none => 'None',
        FilterName.warm => 'Warm',
        FilterName.cool => 'Cool',
        FilterName.mono => 'Mono',
        FilterName.vivid => 'Vivid',
        FilterName.soft => 'Soft',
      };
}
