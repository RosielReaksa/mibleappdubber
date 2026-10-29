import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/dubber_tab_bar.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/dubber_character.dart';
import '../../core/widgets/status_chip.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/library/application/library_controller.dart';
import '../../features/library/domain/library_models.dart';
import '../../features/library/sections/presets_section.dart';
import '../../features/projects/domain/models.dart';
import '../../features/queue/domain/queue_rules.dart';
import 'application/new_project_controller.dart';

class NewProjectScreen extends ConsumerStatefulWidget {
  const NewProjectScreen({super.key, this.templateId, this.presetId});

  final String? templateId;

  /// `?preset=<id>` opens with one of the user's own presets applied.
  final String? presetId;

  @override
  ConsumerState<NewProjectScreen> createState() => _NewProjectScreenState();
}

class _NewProjectScreenState extends ConsumerState<NewProjectScreen> {
  /// True once the screen has asked the server whether it may start.
  bool _rechecked = false;

  /// Dubber templates for the chips row. Empty until loaded; the row then
  /// shows just "None" and any presets.
  List<Template> _templates = const [];
  bool _loadedTemplates = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final controller = ref.read(newProjectControllerProvider.notifier);
      final current = ref.read(newProjectControllerProvider);
      ref.read(authControllerProvider.notifier).refreshMe();
      if (current.languages.isEmpty) await controller.loadContent();
      await _loadTemplates();
      if (widget.templateId != null && current.template == null) {
        await _applyTemplateId(widget.templateId!);
      } else if (widget.presetId != null && current.template == null) {
        await _applyPresetId(widget.presetId!);
      }
      await ref.read(presetLibraryProvider.notifier).load();
    });
  }

  /// Loads the presets too, so the chip row is complete on first paint.
  Future<void> _loadTemplates() async {
    try {
      final templates = await ref.read(apiProvider).templates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loadedTemplates = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadedTemplates = true);
    }
  }

  /// The job that blocked this screen may have finished while the user was
  /// elsewhere. Ask again the first time the screen is shown, so
  /// "Start dubbing" comes back as soon as the queue is empty.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rechecked) return;
    _rechecked = true;
    Future.microtask(
      () => ref.read(newProjectControllerProvider.notifier).checkCanStart(),
    );
  }

  Future<void> _applyTemplateId(String id) async {
    if (_templates.isEmpty) await _loadTemplates();
    final match = _templates.where((t) => t.id == id).firstOrNull;
    if (match != null) {
      ref.read(newProjectControllerProvider.notifier).applyTemplate(match);
    }
  }

  Future<void> _applyPresetId(String id) async {
    await ref.read(presetLibraryProvider.notifier).load();
    final presets = ref.read(presetLibraryProvider).items;
    final match = presets.where((p) => p.id == id).firstOrNull;
    if (match != null) {
      ref.read(newProjectControllerProvider.notifier).applyTemplate(
            match.template,
          );
    }
  }

  Future<void> _pickFile() async {
    final controller = ref.read(newProjectControllerProvider.notifier);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: acceptedExtensions.toList(),
      withData: true,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null) return;

    final path = picked.path ?? '';
    final bytes = picked.bytes;
    if (path.isEmpty && (bytes == null || bytes.isEmpty)) {
      controller.setFileError('We could not read that file.');
      return;
    }
    controller.setFile(
      PickedFile(
        name: picked.name,
        size: picked.size,
        path: path,
        bytes: bytes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newProjectControllerProvider);
    final credits = ref.watch(authControllerProvider).session?.credits;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('New project', style: AppText.display(22)),
                  ),
                  TabHeaderActions(credits: credits),
                ],
              ),
            ),
            Expanded(
              child: state.loadingContent && state.languages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : state.contentError != null && state.languages.isEmpty
                      ? StateView(
                          title: 'We could not load languages',
                          message: state.contentError!.message,
                          mood: CharacterMood.worried,
                          actionLabel: 'Try again',
                          onAction: () => ref
                              .read(newProjectControllerProvider.notifier)
                              .loadContent(),
                        )
                      : _form(state),
            ),
            _startBar(state),
          ],
        ),
      ),
    );
  }

  Widget _form(NewProjectState state) {
    final controller = ref.read(newProjectControllerProvider.notifier);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      children: [
        _TemplateChips(
          templates: _templates,
          presets: ref.watch(presetLibraryProvider).items,
          selectedId: state.template?.id,
          onNone: () =>
              ref.read(newProjectControllerProvider.notifier).clearTemplate(),
          onPick: (template) => ref
              .read(newProjectControllerProvider.notifier)
              .applyTemplate(template),
        ),
        const SizedBox(height: 16),
        if (state.template != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _TemplateBanner(
              name: state.template!.name,
              onChange: () => context.go('/library'),
            ),
          ),
        _FilePickerCard(
          file: state.file,
          error: state.fileError,
          progress: state.uploadProgress,
          onPick: _pickFile,
          onClear: controller.clearFile,
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _LanguageField(
                label: 'From',
                value: state.sourceCode,
                languages: state.languages,
                onChanged: controller.setSource,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LanguageField(
                label: 'To',
                value: state.targetCode,
                languages: state.languages,
                onChanged: controller.setTarget,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _LabeledSection(
          label: 'Video format',
          tagged: state.templateFields.contains('format'),
          child: SegmentedControl<VideoFormat>(
            value: state.format,
            onChanged: controller.setFormat,
            semanticLabel: 'Video format',
            options: const [
              (
                value: VideoFormat.landscape,
                label: 'Landscape 16:9',
                icon: Icons.crop_landscape_rounded
              ),
              (
                value: VideoFormat.portrait,
                label: 'Portrait 9:16',
                icon: Icons.crop_portrait_rounded
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _LabeledSection(
          label: 'Voice',
          child: Column(
            children: [
              for (final choice in VoiceChoice.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _VoiceOption(
                    choice: choice,
                    selected: state.voice == choice,
                    onTap: () => controller.setVoice(choice),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _MixCard(
          mix: state.mix,
          tagged: state.templateFields.contains('mix'),
          onChanged: controller.setMix,
        ),
        const SizedBox(height: 16),
        SecondaryButton(
          label: 'Save as preset',
          icon: Icons.bookmark_add_outlined,
          onPressed: () => savePresetFromNewProject(context, ref),
        ),
        if (state.createError != null) ...[
          const SizedBox(height: 16),
          Text(
            state.createError!.message,
            style: AppText.caption.copyWith(color: Tokens.clayDeep),
          ),
        ],
      ],
    );
  }

  Widget _startBar(NewProjectState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Tokens.ivory,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: state.isBlocked
            ? _BlockedBar(project: state.blockingProject)
            : PrimaryButton(
                label: state.startLabel,
                loading: state.creating,
                onPressed: state.canStart ? () => _start(state) : null,
              ),
      ),
    );
  }

  /// One video. The server re-checks that the user has nothing running.
  Future<void> _start(NewProjectState state) async {
    final controller = ref.read(newProjectControllerProvider.notifier);

    if (state.file == null) {
      controller.setFileError('Choose a video or audio file first.');
      return;
    }

    final outcome = await controller.start();
    if (!mounted) return;

    switch (outcome) {
      case StartOk():
        // The job shows as "Now dubbing" on the Queue tab.
        ref.read(authControllerProvider.notifier).refreshMe();
        context.go('/queue');

      case StartBlocked():
        // The screen is now in the blocked state, with the Queue link.
        break;

      case StartFailed(:final error):
        if (error.code == 'not_enough_credits') {
          await _showNotEnoughCredits(
            needed: state.estimate ?? 0,
            balance: ref.read(authControllerProvider).session?.credits ?? 0,
          );
        }
    }
  }

  Future<void> _showNotEnoughCredits({
    required int needed,
    required int balance,
  }) async {
    final shortfall = (needed - balance).clamp(0, needed);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text('Not enough credits', style: AppText.pageTitle()),
        content: Text(
          'You need $shortfall credits. Buy credits to start this video.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Tokens.muted),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/account/credits');
            },
            style: TextButton.styleFrom(foregroundColor: Tokens.clayButton),
            child: const Text('Buy credits'),
          ),
        ],
      ),
    );
  }
}

/// Replaces the start button while another job is processing or queued.
class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.project});

  final Project? project;

  @override
  Widget build(BuildContext context) {
    final title = project?.title;
    final message = title == null || title.isEmpty
        ? NewProjectState.blockedMessage
        : '"$title" is already dubbing. Add more videos from the Queue tab.';

    return Row(
      children: [
        const Icon(Icons.schedule_rounded, size: 20, color: Tokens.workingText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: AppText.label.copyWith(color: Tokens.muted, height: 1.35),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => context.go('/queue'),
          style: TextButton.styleFrom(
            foregroundColor: Tokens.clayButton,
            minimumSize: const Size(0, Tokens.minTouchTarget),
            textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
          ),
          child: const Text('Open Queue'),
        ),
      ],
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

/// Horizontal chips: None, then Dubber templates, then the user's presets.
///
/// Picking one fills the form and shows the banner/tags through
/// [NewProjectController.applyTemplate], exactly as `/new?template=<id>` does.
class _TemplateChips extends StatelessWidget {
  const _TemplateChips({
    required this.templates,
    required this.presets,
    required this.selectedId,
    required this.onNone,
    required this.onPick,
  });

  final List<Template> templates;
  final List<Preset> presets;
  final String? selectedId;
  final VoidCallback onNone;
  final ValueChanged<Template> onPick;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty && presets.isEmpty) {
      return const SizedBox.shrink();
    }

    final shownPresets = presetsForChips(presets);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          AppChip(
            label: 'None',
            selected: selectedId == null,
            onTap: onNone,
          ),
          for (final template in templates) ...[
            const SizedBox(width: 8),
            AppChip(
              label: template.name,
              selected: selectedId == template.id,
              onTap: () => onPick(template),
            ),
          ],
          for (final preset in shownPresets) ...[
            const SizedBox(width: 8),
            AppChip(
              label: preset.name,
              icon: Icons.bookmark_outline_rounded,
              selected: selectedId == preset.id,
              onTap: () => onPick(preset.template),
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledSection extends StatelessWidget {
  const _LabeledSection({
    required this.label,
    required this.child,
    this.tagged = false,
  });

  final String label;
  final Widget child;
  final bool tagged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.label),
            if (tagged) ...[
              const SizedBox(width: 8),
              const _FromTemplateTag(),
            ],
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _FromTemplateTag extends StatelessWidget {
  const _FromTemplateTag();

  @override
  Widget build(BuildContext context) {
    return Text(
      'From template',
      style: AppText.caption.copyWith(
        color: Tokens.clayButton,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TemplateBanner extends StatelessWidget {
  const _TemplateBanner({required this.name, required this.onChange});

  final String name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Tokens.softClay,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Tokens.clay,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppText.label.copyWith(fontWeight: FontWeight.w600),
                ),
                Text('Settings filled in for you', style: AppText.caption),
              ],
            ),
          ),
          TextButton(
            onPressed: onChange,
            style: TextButton.styleFrom(
              foregroundColor: Tokens.clayButton,
              minimumSize: const Size(0, Tokens.minTouchTarget),
              textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
            ),
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }
}

/// One file: the dashed drop zone, then the chosen file with a remove button.
class _FilePickerCard extends StatelessWidget {
  const _FilePickerCard({
    required this.file,
    required this.error,
    required this.progress,
    required this.onPick,
    required this.onClear,
  });

  final PickedFile? file;
  final String? error;

  /// 0..1 while uploading; null when idle.
  final double? progress;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chosen = file;
    final uploading = progress != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: 110,
          child: CustomPaint(
            painter: _DashedPainter(),
            child: Material(
              color: Tokens.softClay,
              borderRadius: BorderRadius.circular(Tokens.radiusCard),
              child: InkWell(
                onTap: uploading ? null : onPick,
                borderRadius: BorderRadius.circular(Tokens.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        chosen == null
                            ? 'Choose video or audio'
                            : 'Choose another file',
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Tokens.clayDeep,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'MP4, MOV, MP3 · up to 2 GB · 60 minutes',
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            style: AppText.caption.copyWith(color: Tokens.clayDeep),
          ),
        ],
        if (chosen != null) ...[
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Tokens.softClay,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.movie_outlined,
                          size: 18, color: Tokens.clayButton),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chosen.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            uploading
                                ? 'Uploading ${((progress ?? 0) * 100).round()}%'
                                : chosen.sizeLabel,
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    if (!uploading)
                      SizedBox(
                        width: Tokens.minTouchTarget,
                        height: Tokens.minTouchTarget,
                        child: IconButton(
                          onPressed: onClear,
                          tooltip: 'Remove ${chosen.name}',
                          icon: const Icon(Icons.close_rounded,
                              color: Tokens.muted, size: 20),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
                if (uploading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Tokens.oat,
                      valueColor: const AlwaysStoppedAnimation(Tokens.clay),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}


class _DashedPainter extends CustomPainter {
  static Path? _cachedPath;
  static Size? _cachedSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.uploadBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (_cachedSize != size || _cachedPath == null) {
      _cachedSize = size;
      final rawPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Tokens.radiusCard),
        ));
      const dash = 7.0;
      const gap = 5.0;
      final path = Path();
      for (final metric in rawPath.computeMetrics()) {
        var d = 0.0;
        while (d < metric.length) {
          final next = (d + dash).clamp(0.0, metric.length);
          path.addPath(metric.extractPath(d, next), Offset.zero);
          d = next + gap;
        }
      }
      _cachedPath = path;
    }

    canvas.drawPath(_cachedPath!, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LanguageField extends StatelessWidget {
  const _LanguageField({
    required this.label,
    required this.value,
    required this.languages,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Language> languages;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: 6),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Tokens.white,
            borderRadius: BorderRadius.circular(Tokens.radiusField),
            border: Border.all(color: Tokens.borderStrong),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: languages.any((l) => l.code == value) ? value : null,
              isExpanded: true,
              icon: const Icon(Icons.expand_more_rounded, color: Tokens.muted),
              style: AppText.body,
              dropdownColor: Tokens.white,
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              items: [
                for (final language in languages)
                  DropdownMenuItem(
                    value: language.code,
                    child: Text(language.name),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceOption extends StatelessWidget {
  const _VoiceOption({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final VoiceChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (choice) {
      VoiceChoice.female => ('Natural female', null),
      VoiceChoice.male => ('Natural male', null),
      VoiceChoice.auto => (
          'Detect gender automatically',
          'Male and female voices in one video'
        ),
    };

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.all(14),
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
              _Radio(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label.copyWith(fontSize: 15),
                    ),
                    if (subtitle != null) Text(subtitle, style: AppText.caption),
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

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Tokens.clayButton : Tokens.white,
        border: Border.all(
          color: selected ? Tokens.clayButton : Tokens.borderStrong,
          width: 2,
        ),
      ),
      child: selected
          ? const Center(
              child: SizedBox(
                width: 8,
                height: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Tokens.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.mix,
    required this.tagged,
    required this.onChanged,
  });

  final AudioMix mix;
  final bool tagged;
  final ValueChanged<AudioMix> onChanged;

  @override
  Widget build(BuildContext context) {
    final preset = mix.presetName;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Audio mix', style: AppText.label),
              if (tagged) ...[
                const SizedBox(width: 8),
                const _FromTemplateTag(),
              ],
              const Spacer(),
              Text('Drag to adjust', style: AppText.caption),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PresetChip(
                  label: 'Replace voice',
                  selected: preset == 'replace',
                  onTap: () => onChanged(AudioMix.replaceVoice),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetChip(
                  label: 'Voice-over',
                  selected: preset == 'voiceOver',
                  onTap: () => onChanged(AudioMix.voiceOver),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PresetChip(
                  label: 'Keep original',
                  selected: preset == 'keepOriginal',
                  onTap: () => onChanged(AudioMix.keepOriginal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MixSlider(
            label: 'Dubbed voice',
            value: mix.dubbedVoice,
            onChanged: (v) => onChanged(mix.copyWith(dubbedVoice: v)),
          ),
          MixSlider(
            label: 'Original voice',
            value: mix.originalVoice,
            onChanged: (v) => onChanged(mix.copyWith(originalVoice: v)),
          ),
          MixSlider(
            label: 'Background music',
            value: mix.music,
            onChanged: (v) => onChanged(mix.copyWith(music: v)),
          ),
          const SizedBox(height: 4),
          Text(
            'Replace voice starts with the original audio muted. Choose Voice-over or Keep original to retain source audio.',
            style: AppText.caption.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
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
