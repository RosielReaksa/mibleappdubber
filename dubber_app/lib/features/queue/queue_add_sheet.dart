import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/api/api_error.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/controls.dart';
import '../../features/projects/domain/models.dart';
import 'application/queue_add_controller.dart';
import 'domain/dubbing_options.dart';
import 'domain/queue_rules.dart';

/// "Add videos": pick many files, choose the settings once, add.
///
/// Returns `true` to the caller when at least one video was added.
class QueueAddSheet extends ConsumerStatefulWidget {
  const QueueAddSheet({super.key});

  @override
  ConsumerState<QueueAddSheet> createState() => _QueueAddSheetState();
}

class _QueueAddSheetState extends ConsumerState<QueueAddSheet> {
  bool _picked = false;
  bool _loadingContent = true;
  ApiError? _contentError;
  List<Language> _languages = const [];

  String? _sourceCode = 'zh';
  String? _targetCode = 'km';
  VideoFormat _format = VideoFormat.landscape;
  VoiceChoice _voice = VoiceChoice.female;
  AudioMix _mix = const AudioMix();

  /// How many credits one video costs, from the server's estimate.
  int _perFileCredits = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadContent);
  }

  Future<void> _loadContent() async {
    try {
      final api = ref.read(apiProvider);
      final languages = await api.languages();
      if (!mounted) return;
      final defaultSource = languages.any((l) => l.code == 'zh')
          ? 'zh'
          : (languages.isNotEmpty ? languages.first.code : null);
      final defaultTarget = languages.any((l) => l.code == 'km')
          ? 'km'
          : (languages.length > 1 ? languages[1].code : null);
      setState(() {
        _languages = languages;
        _sourceCode = defaultSource;
        _targetCode = defaultTarget;
        _loadingContent = false;
      });
      await _estimate();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contentError = e is ApiError ? e : const ApiError.unknown();
        _loadingContent = false;
      });
    }
  }

  /// One estimate; every video uses the same settings until changed.
  Future<void> _estimate() async {
    if (_sourceCode == null || _targetCode == null) return;
    try {
      final credits = await ref.read(apiProvider).estimate(
            sourceLanguage: _sourceCode!,
            targetLanguage: _targetCode!,
            format: _format,
            voice: _voice,
          );
      if (!mounted) return;
      setState(() => _perFileCredits = credits);
    } catch (_) {
      // The server re-checks on add.
    }
  }

  DubbingOptions get _options => DubbingOptions(
        sourceCode: _sourceCode!,
        targetCode: _targetCode!,
        format: _format,
        voice: _voice,
        mix: _mix,
      );

  @override
  Widget build(BuildContext context) {
    final add = ref.watch(queueAddControllerProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Column(
          children: [
            _grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Add videos', style: AppText.sheetTitle()),
                  ),
                  IconButton(
                    onPressed: add.busy ? null : () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(add, scrollController)),
            _footer(add),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: Tokens.borderStrong,
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
        ),
      );

  Widget _body(QueueAddState add, ScrollController scrollController) {
    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_contentError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('We could not load the options',
                  style: AppText.pageTitle(), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_contentError!.message,
                  style: AppText.bodyMuted, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Try again',
                onPressed: () {
                  setState(() {
                    _loadingContent = true;
                    _contentError = null;
                  });
                  _loadContent();
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      children: [
        if (!_picked)
          _pickZone()
        else ...[
          Text(
            '${add.files.length} files selected',
            style: AppText.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < add.files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FileRow(
                index: i,
                item: add.files[i],
                options: _options,
                languages: _languages,
                onRemove: add.busy
                    ? null
                    : () => ref.read(queueAddControllerProvider.notifier).removeFile(i),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: add.busy ? null : _pickMore,
              style: TextButton.styleFrom(
                foregroundColor: Tokens.clayButton,
                minimumSize: const Size(0, Tokens.minTouchTarget),
                textStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add more files'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Settings for every video',
            style: AppText.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _sharedSettings(),
          if (add.notice != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Tokens.softClay,
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
              ),
              child: Text(add.notice!, style: AppText.label),
            ),
          ],
          if (add.error != null) ...[
            const SizedBox(height: 16),
            Text(
              add.error!.message,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
        ],
      ],
    );
  }

  Widget _pickZone() {
    return SizedBox(
      width: double.infinity,
      height: 150,
      child: Material(
        color: Tokens.softClay,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        child: InkWell(
          onTap: _pickFiles,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.video_library_outlined,
                    size: 30, color: Tokens.clayButton),
                const SizedBox(height: 10),
                Text(
                  'Choose videos',
                  style: AppText.label.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Tokens.clayDeep,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Up to $maxFilesPerAdd at once · ${acceptedExtensions.map((e) => e.toUpperCase()).join(', ')}',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sharedSettings() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Dropdown(
                label: 'From',
                value: _sourceCode,
                items: _languages,
                onChanged: (v) {
                  setState(() => _sourceCode = v);
                  _applyToAll();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Dropdown(
                label: 'To',
                value: _targetCode,
                items: _languages,
                onChanged: (v) {
                  setState(() => _targetCode = v);
                  _applyToAll();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedControl<VideoFormat>(
          value: _format,
          semanticLabel: 'Video format',
          onChanged: (v) {
            setState(() => _format = v);
            _applyToAll();
          },
          options: const [
            (
              value: VideoFormat.landscape,
              label: 'Landscape',
              icon: Icons.crop_landscape_rounded
            ),
            (
              value: VideoFormat.portrait,
              label: 'Portrait',
              icon: Icons.crop_portrait_rounded
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final choice in VoiceChoice.values) ...[
              Expanded(
                child: AppChip(
                  label: switch (choice) {
                    VoiceChoice.female => 'Female',
                    VoiceChoice.male => 'Male',
                    VoiceChoice.auto => 'Auto',
                  },
                  selected: _voice == choice,
                  onTap: () {
                    setState(() => _voice = choice);
                    _applyToAll();
                  },
                ),
              ),
              if (choice != VoiceChoice.auto) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// Pushes the shared settings to every file the user has not locked down.
  void _applyToAll() {
    if (_sourceCode == null || _targetCode == null) return;
    ref.read(queueAddControllerProvider.notifier).applyToAll(_options);
    _estimate();
  }

  Widget _footer(QueueAddState add) {
    final count = add.toSend.length;
    final total = _perFileCredits * count;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Tokens.ivory,
        border: Border(top: BorderSide(color: Tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_picked && add.rejectedCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  add.rejectedCount == 1
                      ? '1 file will not be added. See its reason above.'
                      : '${add.rejectedCount} files will not be added. See their reasons above.',
                  style: AppText.caption.copyWith(color: Tokens.clayDeep),
                ),
              ),
            PrimaryButton(
              label: !_picked
                  ? 'Choose videos'
                  : count == 0
                      ? 'No videos to add'
                      : 'Add $count ${count == 1 ? 'video' : 'videos'}'
                          '${total > 0 ? ' · $total credits' : ''}',
              loading: add.startingUploads,
              onPressed: _picked && add.canStart ? () => _submit(add) : _picked ? null : _pickFiles,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: acceptedExtensions.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final picked = <PickedFile>[];
    for (final f in result.files) {
      if (picked.length >= maxFilesPerAdd) break;
      final path = f.path ?? '';
      final bytes = f.bytes;
      if (path.isEmpty && (bytes == null || bytes.isEmpty)) continue;
      picked.add(PickedFile(name: f.name, size: f.size, path: path, bytes: bytes));
    }
    if (picked.isEmpty || _sourceCode == null || _targetCode == null) return;

    await ref.read(queueAddControllerProvider.notifier).begin(
          files: picked,
          options: _options,
          perFileCredits: _perFileCredits,
        );
    if (!mounted) return;
    setState(() => _picked = true);
    await _estimate();
    if (!mounted) return;
    setState(() {}); // total credits in the button
  }

  Future<void> _pickMore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: acceptedExtensions.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final existing = ref.read(queueAddControllerProvider).files;
    final added = <PickedFile>[];
    for (final f in result.files) {
      if (existing.length + added.length >= maxFilesPerAdd) break;
      final path = f.path ?? '';
      final bytes = f.bytes;
      if (path.isEmpty && (bytes == null || bytes.isEmpty)) continue;
      // Skip files already in the list.
      if (existing.any((e) => (path.isNotEmpty && e.file.path == path) || (path.isEmpty && e.file.name == f.name))) continue;
      added.add(PickedFile(name: f.name, size: f.size, path: path, bytes: bytes));
    }
    if (added.isEmpty) return;

    await ref.read(queueAddControllerProvider.notifier).begin(
          files: [...existing.map((e) => e.file), ...added],
          options: _options,
          perFileCredits: _perFileCredits,
        );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _submit(QueueAddState add) async {
    final response =
        await ref.read(queueAddControllerProvider.notifier).run();
    if (!mounted) return;

    if (response != null && response.added.isNotEmpty) {
      final added = response.added.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added == 1
              ? 'Video added to the queue'
              : '$added videos added to the queue'),
        ),
      );
      Navigator.pop(context, true);
      return;
    }

    // Nothing was added: stay open so the reasons are readable.
    setState(() {});
  }
}

/// One picked file: name, size, state, and a Nudge to change just this one.
class _FileRow extends ConsumerWidget {
  const _FileRow({
    required this.index,
    required this.item,
    required this.options,
    required this.languages,
    this.onRemove,
  });

  final int index;
  final AddFile item;
  final DubbingOptions options;
  final List<Language> languages;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final custom = item.options.sourceCode != options.sourceCode ||
        item.options.targetCode != options.targetCode ||
        item.options.format != options.format ||
        item.options.voice != options.voice;
    final involving = item.state == AddFileState.uploading ||
        item.state == AddFileState.verifying;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.isRejected ? Tokens.softClay : Tokens.oat,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.isRejected
                      ? Icons.error_outline_rounded
                      : item.isAdded
                          ? Icons.check_rounded
                          : Icons.movie_outlined,
                  size: 18,
                  color: item.isRejected ? Tokens.clayDeep : Tokens.clayButton,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(_subtitle(item), style: AppText.caption),
                  ],
                ),
              ),
              if (onRemove != null && !involving)
                SizedBox(
                  width: Tokens.minTouchTarget,
                  height: Tokens.minTouchTarget,
                  child: IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove ${item.file.name}',
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Tokens.muted),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          if (involving) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              child: LinearProgressIndicator(
                value: item.state == AddFileState.verifying ? null : item.progress,
                minHeight: 5,
                backgroundColor: Tokens.oat,
                valueColor: const AlwaysStoppedAnimation(Tokens.clay),
              ),
            ),
          ],
          if (item.isRejected && item.reason != null) ...[
            const SizedBox(height: 6),
            Text(
              item.reason!,
              style: AppText.caption.copyWith(color: Tokens.clayDeep),
            ),
          ],
          if (!item.isRejected && !item.isAdded && !involving) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  custom ? _summary(item.options) : 'Uses the settings below',
                  style: AppText.caption.copyWith(
                    color: custom ? Tokens.clayDeep : Tokens.muted,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _editJustThis(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: Tokens.clayButton,
                    minimumSize: const Size(0, Tokens.minTouchTarget),
                    textStyle:
                        AppText.label.copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: Text(custom ? 'Edit' : 'Change'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(AddFile f) => switch (f.state) {
        AddFileState.added => '${f.file.sizeLabel} · Added',
        AddFileState.uploading =>
          '${f.file.sizeLabel} · Uploading ${(f.progress * 100).round()}%',
        AddFileState.verifying => '${f.file.sizeLabel} · Verifying',
        _ => f.file.sizeLabel,
      };

  String _summary(DubbingOptions o) =>
      '${o.sourceCode.toUpperCase()} → ${o.targetCode.toUpperCase()} · '
      '${o.format == VideoFormat.portrait ? 'Portrait' : 'Landscape'}';

  Future<void> _editJustThis(BuildContext context, WidgetRef ref) async {
    final updated = await showModalBottomSheet<DubbingOptions>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Tokens.radiusCard)),
      ),
      builder: (_) => _OptionsSheet(
        title: item.file.name,
        initial: item.options,
        languages: languages,
      ),
    );
    if (updated == null) return;
    ref.read(queueAddControllerProvider.notifier).applyTo(index, updated);
  }
}

/// Per-video settings, opened from one file row.
class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({
    required this.title,
    required this.initial,
    required this.languages,
  });

  final String title;
  final DubbingOptions initial;
  final List<Language> languages;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late DubbingOptions _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings for this video',
                style: AppText.sheetTitle()),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Dropdown(
                    label: 'From',
                    value: _value.sourceCode,
                    items: widget.languages,
                    onChanged: (v) =>
                        setState(() => _value = _value.copyWith(sourceCode: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Dropdown(
                    label: 'To',
                    value: _value.targetCode,
                    items: widget.languages,
                    onChanged: (v) =>
                        setState(() => _value = _value.copyWith(targetCode: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedControl<VideoFormat>(
              value: _value.format,
              semanticLabel: 'Video format',
              onChanged: (v) => setState(() => _value = _value.copyWith(format: v)),
              options: const [
                (
                  value: VideoFormat.landscape,
                  label: 'Landscape',
                  icon: Icons.crop_landscape_rounded
                ),
                (
                  value: VideoFormat.portrait,
                  label: 'Portrait',
                  icon: Icons.crop_portrait_rounded
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final choice in VoiceChoice.values) ...[
                  Expanded(
                    child: AppChip(
                      label: switch (choice) {
                        VoiceChoice.female => 'Female',
                        VoiceChoice.male => 'Male',
                        VoiceChoice.auto => 'Auto',
                      },
                      selected: _value.voice == choice,
                      onTap: () =>
                          setState(() => _value = _value.copyWith(voice: choice)),
                    ),
                  ),
                  if (choice != VoiceChoice.auto) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Use these settings',
              onPressed: () => Navigator.pop(context, _value),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Language> items;
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
              value: items.any((l) => l.code == value) ? value : null,
              isExpanded: true,
              icon: const Icon(Icons.expand_more_rounded, color: Tokens.muted),
              style: AppText.body,
              dropdownColor: Tokens.white,
              borderRadius: BorderRadius.circular(Tokens.radiusField),
              items: [
                for (final l in items)
                  DropdownMenuItem(value: l.code, child: Text(l.name)),
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