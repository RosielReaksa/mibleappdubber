import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/dubber_character.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/library_controller.dart';
import '../domain/library_models.dart';
import '../widgets/library_widgets.dart';

/// Library section for saved video logos.
class LogosSection extends ConsumerStatefulWidget {
  const LogosSection({super.key});

  @override
  ConsumerState<LogosSection> createState() => _LogosSectionState();
}

class _LogosSectionState extends ConsumerState<LogosSection> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted || _loaded) return;
      _loaded = true;
      ref.read(logoLibraryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(logoLibraryProvider, (previous, next) {
      final error = next.error;
      if (error != null && previous?.error != error && mounted) {
        showLibrarySnack(context, error.message);
      }
    });
    final state = ref.watch(logoLibraryProvider);
    final controller = ref.read(logoLibraryProvider.notifier);

    return LibraryBody<SavedLogo>(
      state: state,
      emptyTitle: 'No logos yet',
      emptyMessage: 'Add the logo you put on your videos and reuse it in the editor.',
      emptyAction: 'Add logo',
      onAction: state.canMutate ? _addLogo : () {},
      errorTitle: 'We could not load your logos',
      onRetry: controller.load,
      builder: (context, logos) => LogosGrid(
        logos: logos,
        offline: state.offline,
        canMutate: state.canMutate,
        onAdd: _addLogo,
        onDelete: _deleteLogo,
      ),
    );
  }

  Future<void> _addLogo() async {
    final state = ref.read(logoLibraryProvider);
    if (!state.canMutate) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final file = result?.files.firstOrNull;
    final path = file?.path;
    if (file == null || path == null || !mounted) return;

    final extension = file.name.lastIndexOf('.');
    final initial = extension > 0 ? file.name.substring(0, extension) : file.name;
    final name = await showNameDialog(
      context,
      title: 'Name your logo',
      hint: 'Logo name',
      initial: initial,
      confirmLabel: 'Add logo',
    );
    if (name == null || !mounted || !ref.read(logoLibraryProvider).canMutate) return;

    final logo = SavedLogo(
      id: 'logo_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      url: path,
    );
    final resultMutation = await ref.read(logoLibraryProvider.notifier).create(logo);
    if (mounted) {
      showLibrarySnack(context, mutationMessage(resultMutation, done: 'Logo added'));
    }
  }

  Future<void> _deleteLogo(SavedLogo logo) async {
    if (!ref.read(logoLibraryProvider).canMutate) return;
    final confirmed = await confirmDelete(
      context,
      title: 'Delete logo?',
      message: '"${logo.name}" will be removed from your Library. Videos that already use it are not changed.',
    );
    if (!confirmed || !mounted || !ref.read(logoLibraryProvider).canMutate) return;
    final result = await ref.read(logoLibraryProvider.notifier).delete(logo.id);
    if (mounted) {
      showLibrarySnack(context, mutationMessage(result, done: 'Logo deleted'));
    }
  }
}

/// Bottom sheet that lets the editor's Logo tool pick a saved logo.
///
/// Shows the same four states as the Library section, so an offline or empty
/// Library never leaves the editor stuck with a blank sheet.
Future<void> showLogoPickerSheet(
  BuildContext context, {
  required void Function(SavedLogo) onPick,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.ivory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _LogoPickerSheet(
      onPick: (logo) {
        onPick(logo);
        Navigator.pop(sheetContext);
      },
    ),
  );
}

class _LogoPickerSheet extends ConsumerStatefulWidget {
  const _LogoPickerSheet({required this.onPick});

  final ValueChanged<SavedLogo> onPick;

  @override
  ConsumerState<_LogoPickerSheet> createState() => _LogoPickerSheetState();
}

class _LogoPickerSheetState extends ConsumerState<_LogoPickerSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(logoLibraryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(logoLibraryProvider);
    final controller = ref.read(logoLibraryProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose from Library', style: AppText.sheetTitle()),
            const SizedBox(height: 14),
            if (state.offline && state.items.isNotEmpty)
              const OfflineBanner(),
            if (state.phase == LibraryPhase.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            else if (state.phase == LibraryPhase.error)
              StateView(
                title: 'We could not load your logos',
                message: state.error?.message ?? 'Please try again.',
                mood: CharacterMood.worried,
                actionLabel: 'Try again',
                onAction: controller.load,
                compact: true,
              )
            else if (state.items.isEmpty)
              StateView(
                title: 'No logos yet',
                message: 'Add a logo in the Library tab, then pick it here.',
                compact: true,
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: state.items.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 96,
                  ),
                  itemBuilder: (context, i) {
                    final logo = state.items[i];
                    return Semantics(
                      button: true,
                      label: 'Choose logo ${logo.name}',
                      child: InkWell(
                        onTap: () => widget.onPick(logo),
                        borderRadius:
                            BorderRadius.circular(Tokens.radiusButton),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Tokens.white,
                            borderRadius:
                                BorderRadius.circular(Tokens.radiusButton),
                            border: Border.all(color: Tokens.border),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: _LogoImage(
                                    logo: logo,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                logo.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Presentational grid used by the section and state-focused widget tests.
class LogosGrid extends StatelessWidget {
  const LogosGrid({
    super.key,
    required this.logos,
    required this.offline,
    required this.canMutate,
    required this.onAdd,
    required this.onDelete,
  });

  final List<SavedLogo> logos;
  final bool offline;
  final bool canMutate;
  final VoidCallback onAdd;
  final ValueChanged<SavedLogo> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = (constraints.maxWidth - 40 - 20) / 3;
        return Column(
          children: [
            if (offline && logos.isNotEmpty) const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SecondaryButton(
                  label: 'Add logo',
                  icon: Icons.add_photo_alternate_outlined,
                  onPressed: canMutate ? onAdd : null,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: logos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: extent,
                ),
                itemBuilder: (context, index) => _LogoCell(
                  logo: logos[index],
                  canMutate: canMutate,
                  onDelete: () => onDelete(logos[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogoCell extends StatelessWidget {
  const _LogoCell({required this.logo, required this.canMutate, required this.onDelete});

  final SavedLogo logo;
  final bool canMutate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tokens.white,
      borderRadius: BorderRadius.circular(Tokens.radiusButton),
      child: PopupMenuButton<String>(
        enabled: canMutate,
        tooltip: 'Logo actions for ${logo.name}',
        onSelected: (_) => onDelete(),
        itemBuilder: (_) =>
            const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox.expand(
                    child: _LogoImage(logo: logo, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                logo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The logo image, whether the server gave a URL or the file is still local.
class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.logo, required this.fit});

  final SavedLogo logo;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = logo.url;
    if (path != null && path.startsWith('http')) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: Tokens.oat,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: Tokens.muted),
      );
}
