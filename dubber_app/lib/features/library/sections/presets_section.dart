import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../new_project/application/new_project_controller.dart';
import '../../projects/domain/models.dart';
import '../application/library_controller.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';
import '../widgets/library_widgets.dart';

/// Library section for reusable New project settings.
class PresetsSection extends ConsumerStatefulWidget {
  const PresetsSection({super.key});

  @override
  ConsumerState<PresetsSection> createState() => _PresetsSectionState();
}

class _PresetsSectionState extends ConsumerState<PresetsSection> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted || _loaded) return;
      _loaded = true;
      ref.read(presetLibraryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(presetLibraryProvider, (previous, next) {
      final error = next.error;
      if (error != null && previous?.error != error && mounted) {
        showLibrarySnack(context, error.message);
      }
    });
    final state = ref.watch(presetLibraryProvider);
    final controller = ref.read(presetLibraryProvider.notifier);

    return LibraryBody<Preset>(
      state: state,
      emptyTitle: 'No presets yet',
      emptyMessage: 'A preset saves your New project settings (format, subtitles, mix, fit, logo) so you can reuse them in one tap.',
      emptyAction: 'Save as preset',
      onAction: state.canMutate ? () => savePresetFromNewProject(context, ref) : () {},
      errorTitle: 'We could not load your presets',
      onRetry: controller.load,
      builder: (context, presets) => PresetsList(
        presets: presets,
        offline: state.offline,
        canMutate: state.canMutate,
        onSave: () => savePresetFromNewProject(context, ref),
        onRename: _rename,
        onDelete: _delete,
      ),
    );
  }

  Future<void> _rename(Preset preset) async {
    final state = ref.read(presetLibraryProvider);
    if (!state.canMutate) return;
    final name = await showNameDialog(
      context,
      title: 'Rename preset',
      hint: 'Preset name',
      initial: preset.name,
      confirmLabel: 'Rename',
    );
    if (name == null || !mounted || !ref.read(presetLibraryProvider).canMutate) return;
    final result = await ref.read(presetLibraryProvider.notifier).rename(preset.id, name);
    if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Preset renamed'));
  }

  Future<void> _delete(Preset preset) async {
    if (!ref.read(presetLibraryProvider).canMutate) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Delete preset?',
      message: '"${preset.name}" will be removed from your Library.',
    );
    if (!confirmed || !mounted || !ref.read(presetLibraryProvider).canMutate) return;
    final result = await ref.read(presetLibraryProvider.notifier).delete(preset.id);
    if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Preset deleted'));
  }
}

/// Saves the current New project format and mix; subtitle, fit, and logo
/// settings are included when those fields are added to [NewProjectState].
Future<bool> savePresetFromNewProject(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(presetLibraryProvider.notifier);
  if (!ref.read(presetLibraryProvider).canMutate) return false;
  final state = ref.read(newProjectControllerProvider);
  final suggested = '${_formatName(state.format)} · ${_mixName(state.mix)}';
  final name = await showNameDialog(
    context,
    title: 'Save as preset',
    hint: 'Preset name',
    initial: suggested,
    confirmLabel: 'Save preset',
  );
  if (name == null || !context.mounted || !ref.read(presetLibraryProvider).canMutate) return false;

  final preset = Preset.fromNewProject(
    id: 'preset_${DateTime.now().microsecondsSinceEpoch}',
    name: name,
    format: state.format,
    mix: state.mix,
  );
  final result = await controller.create(preset);
  if (!context.mounted) return false;
  showLibrarySnack(context, mutationMessage(result, done: 'Preset saved'));
  return result is! MutationFailed;
}

String _formatName(VideoFormat format) => switch (format) {
      VideoFormat.landscape => 'Landscape',
      VideoFormat.portrait => 'Portrait',
    };

String _mixName(AudioMix mix) => switch (mix.presetName) {
      'replace' => 'Replace voice',
      'voiceOver' => 'Voice-over',
      'keepOriginal' => 'Keep original',
      _ => 'Custom mix',
    };

/// Presets displayed in the New screen, newest first and capped at [limit].
List<Preset> presetsForChips(List<Preset> list, {int limit = 8}) {
  final sorted = [...list]..sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
  return sorted.take(limit < 0 ? 0 : limit).toList();
}

int _createdAt(Preset preset) =>
    preset.createdAt?.microsecondsSinceEpoch ??
    int.tryParse(preset.id.startsWith('preset_') ? preset.id.substring(7) : '') ?? 0;

/// Presentational preset list used by the Library section and widget tests.
class PresetsList extends StatelessWidget {
  const PresetsList({
    super.key,
    required this.presets,
    required this.offline,
    required this.canMutate,
    required this.onSave,
    required this.onRename,
    required this.onDelete,
  });

  final List<Preset> presets;
  final bool offline;
  final bool canMutate;
  final VoidCallback onSave;
  final ValueChanged<Preset> onRename;
  final ValueChanged<Preset> onDelete;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (offline && presets.isNotEmpty) const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SecondaryButton(
                label: 'Save as preset',
                icon: Icons.bookmark_add_outlined,
                onPressed: canMutate ? onSave : null,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final preset = presets[index];
                return _PresetCard(
                  preset: preset,
                  canMutate: canMutate,
                  onRename: () => onRename(preset),
                  onDelete: () => onDelete(preset),
                  onUse: () => context.go('/new?preset=${preset.id}'),
                );
              },
            ),
          ),
        ],
      );
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.canMutate,
    required this.onRename,
    required this.onDelete,
    required this.onUse,
  });

  final Preset preset;
  final bool canMutate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        decoration: BoxDecoration(
          color: Tokens.white,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          border: Border.all(color: Tokens.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.name, style: AppText.label),
                  const SizedBox(height: 3),
                  Text(
                    presetSummary(preset.template),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: canMutate,
              tooltip: 'Preset actions for ${preset.name}',
              onSelected: (action) {
                switch (action) {
                  case 'rename': onRename();
                  case 'delete': onDelete();
                  case 'use': onUse();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
                PopupMenuItem(value: 'use', child: Text('Use in New project')),
              ],
            ),
          ],
        ),
      );
}

/// A compact summary that omits settings which are not present.
String presetSummary(Template template) {
  final parts = <String>[];
  if (template.format != null) parts.add(_formatName(template.format!));
  if (template.subtitlesOn && template.subtitleStyle != null) {
    parts.add('${_cap(template.subtitleStyle!)} subtitles');
  } else if (template.subtitlesOn) {
    parts.add('Subtitles');
  }
  if (template.mix != null) parts.add(_mixName(template.mix!));
  if (template.fitMode != null) {
    parts.add('${_cap(template.fitMode!)} fit');
  }
  if (template.logoPosition != null) parts.add('Logo ${_positionName(template.logoPosition!)}');
  return parts.join(' · ');
}

String _cap(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _positionName(String position) => switch (position) {
      'top_right' => 'top right',
      'top_left' => 'top left',
      'bottom_right' => 'bottom right',
      'bottom_left' => 'bottom left',
      _ => position.replaceAll('_', ' '),
    };
