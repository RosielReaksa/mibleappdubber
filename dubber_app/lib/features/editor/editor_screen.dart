import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../projects/domain/models.dart';
import 'application/editor_controller.dart';
import 'widgets/editor_preview.dart';
import 'tools/tool_panels.dart';

/// Editor shell: preview, active tool panel, and the scrolling tool bar.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadProject);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Bring the tool panel into view when a tool is picked, so its controls
  /// are never hidden below the fold on short screens.
  void _selectTool(EditorTool tool) {
    ref.read(editorControllerProvider(widget.projectId).notifier).selectTool(tool);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadProject() async {
    try {
      final project = await ref.read(apiProvider).project(widget.projectId);
      final controller = ref.read(editorControllerProvider(widget.projectId).notifier);
      // The editor starts with the mix the user chose in New project.
      controller.setMix(project.mix);
      controller.setFormat(project.format);
    } catch (_) {
      // Fall back to defaults; the preview still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorControllerProvider(widget.projectId));
    final controller = ref.read(editorControllerProvider(widget.projectId).notifier);

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscard();
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: Tokens.ivory,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                onBack: () async {
                  if (!state.dirty) {
                    context.pop();
                    return;
                  }
                  final leave = await _confirmDiscard();
                  if (leave && context.mounted) context.pop();
                },
                onExport: () => _export(state),
                exporting: state.exporting,
              ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    SegmentedControl<VideoFormat>(
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
                    const SizedBox(height: 14),
                    EditorPreview(state: state, onMoveText: controller.moveText),
                    const SizedBox(height: 14),
                    _Timeline(state: state, controller: controller),
                    const SizedBox(height: 14),
                    if (state.error != null) ...[
                      Text(
                        state.error!,
                        style: AppText.caption.copyWith(color: Tokens.clayDeep),
                      ),
                      const SizedBox(height: 10),
                    ],
                    ToolPanel(state: state, controller: controller),
                  ],
                ),
              ),
              _ToolBar(
                selected: state.tool,
                onSelect: _selectTool,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        title: Text('Discard changes?', style: AppText.pageTitle()),
        content: const Text(
          'Your edits have not been exported yet.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Tokens.muted),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Tokens.clayDeep),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _export(EditorState state) async {
    final controller =
        ref.read(editorControllerProvider(widget.projectId).notifier);
    controller.setExporting(true);
    try {
      final exportId = await ref.read(apiProvider).startExport(
            projectId: widget.projectId,
            settings: state.toExportSettings(),
          );
      controller.markSaved();
      controller.setExporting(false);
      if (!mounted) return;
      context.push('/projects/${widget.projectId}/export/$exportId');
    } catch (e) {
      controller.setError('We could not start the export. Please try again.');
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onExport,
    required this.exporting,
  });

  final VoidCallback onBack;
  final VoidCallback onExport;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          SizedBox(
            width: Tokens.minTouchTarget,
            height: Tokens.minTouchTarget,
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, size: 26),
            ),
          ),
          Expanded(child: Text('Edit video', style: AppText.display(22))),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: exporting ? null : onExport,
              style: FilledButton.styleFrom(
                backgroundColor: Tokens.clayButton,
                foregroundColor: Tokens.white,
                disabledBackgroundColor: Tokens.clayButton.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: AppText.button.copyWith(fontSize: 15),
              ),
              child: exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Tokens.white),
                      ),
                    )
                  : const Text('Export'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.state, required this.controller});

  final EditorState state;
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final duration = (state.trimEnd - state.trimStart).clamp(0.1, 100000);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Tokens.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Tokens.border, blurRadius: 0, spreadRadius: 1),
            ],
          ),
          child: const Icon(Icons.play_arrow_rounded,
              size: 20, color: Tokens.clayButton),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            child: LinearProgressIndicator(
              value: 0.14,
              minHeight: 8,
              backgroundColor: Tokens.oat,
              valueColor: const AlwaysStoppedAnimation(Tokens.clay),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${_fmt(state.trimStart)} / ${_fmt(state.trimStart + duration)}',
          style: AppText.caption.copyWith(fontSize: 13),
        ),
      ],
    );
  }

  String _fmt(double seconds) {
    final total = seconds.round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.selected, required this.onSelect});

  final EditorTool selected;
  final ValueChanged<EditorTool> onSelect;

  static const _tools = [
    (tool: EditorTool.text, label: 'Text', icon: Icons.title_rounded),
    (tool: EditorTool.logo, label: 'Logo', icon: Icons.image_outlined),
    (tool: EditorTool.subtitles, label: 'Subtitles', icon: Icons.subtitles_outlined),
    (tool: EditorTool.trim, label: 'Trim', icon: Icons.content_cut_rounded),
    (tool: EditorTool.audio, label: 'Audio', icon: Icons.graphic_eq_rounded),
    (tool: EditorTool.blur, label: 'Blur', icon: Icons.blur_on_rounded),
    (tool: EditorTool.fit, label: 'Fit', icon: Icons.aspect_ratio_rounded),
    (tool: EditorTool.filters, label: 'Filters', icon: Icons.filter_vintage_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Tokens.white,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final entry in _tools)
                _ToolButton(
                  label: entry.label,
                  icon: entry.icon,
                  selected: entry.tool == selected,
                  onTap: () => onSelect(entry.tool),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Tokens.clayButton : Tokens.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 64,
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? Tokens.softClay : Colors.transparent,
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppText.chip.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
