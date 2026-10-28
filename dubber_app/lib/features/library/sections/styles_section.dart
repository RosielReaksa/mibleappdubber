import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/widgets/dubber_character.dart';
import '../../editor/application/editor_controller.dart';
import '../application/library_controller.dart';
import '../domain/library_models.dart';
import '../widgets/library_widgets.dart';

/// Library section for saved text and subtitle styles.
class StylesSection extends ConsumerStatefulWidget {
  const StylesSection({super.key});

  @override
  ConsumerState<StylesSection> createState() => _StylesSectionState();
}

class _StylesSectionState extends ConsumerState<StylesSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(styleLibraryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(styleLibraryProvider);
    final controller = ref.read(styleLibraryProvider.notifier);
    return LibraryBody<SavedStyle>(
      state: state,
      emptyTitle: 'No saved styles',
      emptyMessage: 'Save the text and subtitle styles you like and apply them in the editor.',
      emptyAction: 'Create style',
      onAction: state.canMutate ? _create : () {},
      errorTitle: 'We could not load your styles',
      onRetry: controller.load,
      builder: (context, styles) => StylesList(
        styles: styles,
        offline: state.offline,
        canMutate: state.canMutate,
        onCreate: _create,
        onRename: _rename,
        onDelete: _delete,
      ),
    );
  }

  Future<void> _create() async {
    if (!ref.read(styleLibraryProvider).canMutate) return;
    final style = await showStyleEditorSheet(context);
    if (style == null || !mounted || !ref.read(styleLibraryProvider).canMutate) return;
    final result = await ref.read(styleLibraryProvider.notifier).create(style);
    if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style saved'));
  }

  Future<void> _rename(SavedStyle style) async {
    if (!ref.read(styleLibraryProvider).canMutate) return;
    final name = await showNameDialog(context, title: 'Rename style', hint: 'Style name', initial: style.name);
    if (name == null || !mounted || !ref.read(styleLibraryProvider).canMutate) return;
    final result = await ref.read(styleLibraryProvider.notifier).rename(style.id, name);
    if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style renamed'));
  }

  Future<void> _delete(SavedStyle style) async {
    if (!ref.read(styleLibraryProvider).canMutate) return;
    final confirmed = await confirmDelete(context, title: 'Delete style?', message: '"${style.name}" will be removed from your Library.');
    if (!confirmed || !mounted || !ref.read(styleLibraryProvider).canMutate) return;
    final result = await ref.read(styleLibraryProvider.notifier).delete(style.id);
    if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style deleted'));
  }
}

/// Presentational list of styles, exposed for state-focused tests.
class StylesList extends StatelessWidget {
  const StylesList({super.key, required this.styles, required this.offline, required this.canMutate, required this.onCreate, required this.onRename, required this.onDelete});

  final List<SavedStyle> styles;
  final bool offline;
  final bool canMutate;
  final VoidCallback onCreate;
  final ValueChanged<SavedStyle> onRename;
  final ValueChanged<SavedStyle> onDelete;

  @override
  Widget build(BuildContext context) {
    final textStyles = styles.where((s) => s.kind == StyleKind.text).toList();
    final subtitleStyles = styles.where((s) => s.kind == StyleKind.subtitle).toList();
    return Column(children: [
      if (offline && styles.isNotEmpty) const OfflineBanner(),
      Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: Align(alignment: Alignment.centerLeft, child: SecondaryButton(label: 'Add style', icon: Icons.add, onPressed: canMutate ? onCreate : null))),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        if (textStyles.isNotEmpty) ...[_heading('Text'), for (final style in textStyles) _StyleRow(style: style, canMutate: canMutate, onRename: () => onRename(style), onDelete: () => onDelete(style))],
        if (subtitleStyles.isNotEmpty) ...[_heading('Subtitles'), for (final style in subtitleStyles) _StyleRow(style: style, canMutate: canMutate, onRename: () => onRename(style), onDelete: () => onDelete(style))],
      ])),
    ]);
  }

  Widget _heading(String value) => Padding(padding: const EdgeInsets.only(bottom: 8, top: 8), child: Text(value, style: AppText.labelMuted));
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({required this.style, required this.canMutate, required this.onRename, required this.onDelete});
  final SavedStyle style;
  final bool canMutate;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTileCard(child: Row(children: [
      _StyleSwatch(style: style),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(style.name, style: AppText.label.copyWith(fontWeight: FontWeight.w600)), Text(style.summary, style: AppText.caption)])),
      PopupMenuButton<String>(enabled: canMutate, tooltip: 'Style actions for ${style.name}', icon: const Icon(Icons.more_horiz), onSelected: (v) => v == 'rename' ? onRename() : onDelete(), itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
    ])),
  );
}

class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style});

  final SavedStyle style;

  @override
  Widget build(BuildContext context) {
    final box = style.kind == StyleKind.subtitle &&
        style.subtitleStyle == SubtitleStyle.box;
    final textColor = style.kind == StyleKind.text
        ? _hexColor(style.color)
        : Tokens.ink;

    // A text style previews its own color: the swatch is filled with it and
    // the "Aa" is drawn in whichever of ink/white stays readable.
    final background = box
        ? Tokens.ink
        : style.kind == StyleKind.text
            ? textColor
            : Tokens.oat;
    final glyphColor = box
        ? Tokens.white
        : style.kind == StyleKind.text
            ? _contrastOn(textColor)
            : Tokens.ink;

    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Tokens.border),
      ),
      child: Text(
        'Aa',
        style: TextStyle(
          fontFamily: Tokens.fontHeading,
          fontSize: 20,
          fontWeight: style.subtitleStyle == SubtitleStyle.bold
              ? FontWeight.w700
              : FontWeight.w500,
          color: glyphColor,
        ),
      ),
    );
  }

  /// Ink on light colors, white on dark ones.
  static Color _contrastOn(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? Tokens.ink : Tokens.white;
  }
}

Color _hexColor(String hex) => Color(0xFF000000 | (int.tryParse(hex.replaceAll('#', ''), radix: 16) ?? 0xFFFFFF));

/// Opens the shared create-style sheet and returns its unsaved style.
Future<SavedStyle?> showStyleEditorSheet(BuildContext context) => showModalBottomSheet<SavedStyle>(
  context: context, isScrollControlled: true, backgroundColor: Tokens.ivory,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (_) => const _StyleEditorSheet(),
);

class _StyleEditorSheet extends ConsumerStatefulWidget {
  const _StyleEditorSheet();
  @override
  ConsumerState<_StyleEditorSheet> createState() => _StyleEditorSheetState();
}

class _StyleEditorSheetState extends ConsumerState<_StyleEditorSheet> {
  final _name = TextEditingController();
  StyleKind _kind = StyleKind.text;
  int _size = 60;
  String _color = '#FFFFFF';
  SubtitleStyle _subtitleStyle = SubtitleStyle.classic;

  static const _colors = ['#FFFFFF', '#141413', '#D97757', '#F6E7C6'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Typing must re-evaluate the Save button, so the name is watched rather
    // than read once during build.
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create style', style: AppText.sheetTitle()),
              const SizedBox(height: 16),
              SegmentedControl<StyleKind>(
                options: const [
                  (value: StyleKind.text, label: 'Text', icon: null),
                  (value: StyleKind.subtitle, label: 'Subtitles', icon: null),
                ],
                value: _kind,
                onChanged: (v) => setState(() => _kind = v),
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Name',
                controller: _name,
                hint: 'Style name',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              MixSlider(
                label: 'Size',
                value: _size,
                onChanged: (v) => setState(() => _size = v),
              ),
              if (_kind == StyleKind.text) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final hex in _colors)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _StyleColorDot(
                          hex: hex,
                          selected: _color == hex,
                          onTap: () => setState(() => _color = hex),
                        ),
                      ),
                  ],
                ),
              ],
              if (_kind == StyleKind.subtitle) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in SubtitleStyle.values)
                      AppChip(
                        label: _cap(s.name),
                        selected: s == _subtitleStyle,
                        onTap: () => setState(() => _subtitleStyle = s),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: _StyleSwatch(
                  style: SavedStyle(
                    id: '',
                    name: '',
                    kind: _kind,
                    size: _size,
                    color: _color,
                    subtitleStyle: _subtitleStyle,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Save style',
                onPressed: _name.text.trim().isEmpty ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    Navigator.pop(
      context,
      SavedStyle(
        id: 'style_${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        kind: _kind,
        size: _size,
        color: _color,
        subtitleStyle: _subtitleStyle,
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _StyleColorDot extends StatelessWidget {
  const _StyleColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            color: _hexColor(hex),
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

/// Shows saved styles matching the selected editor tool.
Future<void> showApplyStyleSheet(BuildContext context, WidgetRef ref, {required EditorTool tool, required void Function(SavedStyle) onApply}) async {
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Tokens.ivory, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (sheetContext) => _ApplyStylesSheet(tool: tool, onApply: (style) { onApply(style); Navigator.pop(sheetContext); }));
}

class _ApplyStylesSheet extends ConsumerStatefulWidget {
  const _ApplyStylesSheet({required this.tool, required this.onApply});
  final EditorTool tool; final ValueChanged<SavedStyle> onApply;
  @override
  ConsumerState<_ApplyStylesSheet> createState() => _ApplyStylesSheetState();
}
class _ApplyStylesSheetState extends ConsumerState<_ApplyStylesSheet> {
  @override
  void initState() { super.initState(); Future.microtask(() { if (mounted) ref.read(styleLibraryProvider.notifier).load(); }); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(styleLibraryProvider); final controller = ref.read(styleLibraryProvider.notifier);
    final kind = widget.tool == EditorTool.subtitles ? StyleKind.subtitle : StyleKind.text;
    final styles = state.items.where((s) => s.kind == kind).toList();
    return SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Apply saved style', style: AppText.sheetTitle()), const SizedBox(height: 12),
      if (state.offline && styles.isNotEmpty) const OfflineBanner(),
      if (state.phase == LibraryPhase.loading) const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
      else if (state.phase == LibraryPhase.error) StateView(title: 'We could not load your styles', message: state.error?.message ?? 'Please try again.', mood: CharacterMood.worried, actionLabel: 'Try again', onAction: controller.load, compact: true)
      else if (styles.isEmpty) StateView(title: 'No saved styles yet', message: 'Save one from the editor', actionLabel: 'Create style', onAction: state.canMutate ? () async { final style = await showStyleEditorSheet(context); if (style != null && mounted && ref.read(styleLibraryProvider).canMutate) { final result = await controller.create(style); if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style saved')); } } : () {}, compact: true)
      else ...[for (final style in styles) ListTileCard(child: ListTile(leading: _StyleSwatch(style: style), title: Text(style.name), subtitle: Text(style.summary), onTap: () => widget.onApply(style)))],
      if (state.phase != LibraryPhase.loading && state.phase != LibraryPhase.error) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: state.canMutate ? () async { final style = await showStyleEditorSheet(context); if (style != null && mounted && ref.read(styleLibraryProvider).canMutate) { final result = await controller.create(style); if (mounted) showLibrarySnack(context, mutationMessage(result, done: 'Style saved')); } } : null, child: const Text('Create style'))),
    ])));
  }
}

/// Opens the shared name dialog for saving a style from the editor.
Future<String?> askStyleName(BuildContext context, {required String initial}) => showNameDialog(context, title: 'Save as style', hint: 'Style name', initial: initial, confirmLabel: 'Save style');

/// Maps a saved subtitle style to the editor enum.
SubtitleStyle subtitleStyleFor(SavedStyle style) => style.subtitleStyle;
