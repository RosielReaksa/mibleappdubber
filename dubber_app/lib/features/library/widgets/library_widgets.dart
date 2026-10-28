import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/router/dubber_tab_bar.dart';
import '../../../core/api/api_error.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/dubber_character.dart';
import '../../../core/widgets/status_chip.dart';
import '../application/library_controller.dart';
import '../data/library_repository.dart';

/// Shared chrome for the Library screen: title, credits, Help, avatar.
///
/// The Help button is always present and always 44x44 with the label "Help",
/// so it meets the touch-target rule in the spec.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.credits,
    required this.onHelp,
    required this.onAccount,
    required this.onCredits,
  });

  final int? credits;
  final VoidCallback onHelp;
  final VoidCallback onAccount;
  final VoidCallback onCredits;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Expanded(child: Text('Library', style: AppText.display(28))),
          Semantics(
            button: true,
            label: 'Help',
            child: SizedBox(
              width: Tokens.minTouchTarget,
              height: Tokens.minTouchTarget,
              child: Tooltip(
                message: 'Help',
                child: InkWell(
                  onTap: onHelp,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: Tokens.minTouchTarget,
                    height: Tokens.minTouchTarget,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Tokens.borderStrong),
                    ),
                    child: const Icon(
                      Icons.question_mark_rounded,
                      size: 18,
                      color: Tokens.clayButton,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TabHeaderActions(
            credits: credits,
            onCredits: onCredits,
            onAccount: onAccount,
          ),
        ],
      ),
    );
  }
}

/// The four-section segmented control under the Library title.
class LibrarySections extends StatelessWidget {
  const LibrarySections({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LibrarySection value;
  final ValueChanged<LibrarySection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Library sections',
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Tokens.segmentBg,
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
        ),
        child: Row(
          children: [
            for (final section in LibrarySection.values)
              Expanded(
                child: _Segment(
                  label: section.label,
                  selected: section == value,
                  onTap: () => onChanged(section),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The four sections in display order.
enum LibrarySection {
  templates('Templates'),
  logos('Logos'),
  styles('Styles'),
  presets('My presets');

  const LibrarySection(this.label);
  final String label;
}

extension LibrarySectionX on LibrarySection {
  /// `?section=logos` opens Logos; anything else opens Templates.
  static LibrarySection fromWire(String? wire) => switch (wire) {
        'logos' => LibrarySection.logos,
        'styles' => LibrarySection.styles,
        'presets' => LibrarySection.presets,
        _ => LibrarySection.templates,
      };
}

class _Segment extends StatelessWidget {
  const _Segment({
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
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Tokens.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Tokens.fontBody,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Tokens.ink : Tokens.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Calm banner shown above a cached list when the server is unreachable.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Tokens.workingBg,
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 18, color: Tokens.workingText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline. Showing saved items. Adding and deleting are paused.',
              style: AppText.caption.copyWith(
                color: Tokens.workingText,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading / empty / error bodies shared by the sections.
///
/// The four-state rule lives here: a section passes its [LibraryState] and its
/// empty copy, and gets the right body back. Offline is rendered by the caller
/// as a banner over the cached list (see [OfflineBanner]).
class LibraryBody<T> extends StatelessWidget {
  const LibraryBody({
    super.key,
    required this.state,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyAction,
    required this.onAction,
    required this.errorTitle,
    required this.onRetry,
    required this.builder,
  });

  final LibraryState<T> state;
  final String emptyTitle;
  final String emptyMessage;
  final String emptyAction;
  final VoidCallback onAction;
  final String errorTitle;
  final VoidCallback onRetry;
  final Widget Function(BuildContext context, List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case LibraryPhase.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
      case LibraryPhase.error:
        return StateView(
          title: errorTitle,
          message: state.error?.message ?? 'Please try again.',
          mood: CharacterMood.worried,
          actionLabel: 'Try again',
          onAction: onRetry,
          compact: true,
        );
      case LibraryPhase.empty:
        return StateView(
          title: emptyTitle,
          message: emptyMessage,
          actionLabel: emptyAction,
          onAction: onAction,
          compact: true,
        );
      case LibraryPhase.ready:
        return builder(context, state.items);
    }
  }
}

/// Small dialog used by the sections for create and rename.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      title: Text(title, style: AppText.pageTitle()),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) {
          final name = v.trim();
          if (name.isNotEmpty) Navigator.pop(context, name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Tokens.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          style: TextButton.styleFrom(foregroundColor: Tokens.clayButton),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Confirms a destructive action. Returns true when the user agrees.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Tokens.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      title: Text(title, style: AppText.pageTitle()),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: Tokens.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: Tokens.clayDeep),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Toast-like message used after a mutation.
void showLibrarySnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppText.label.copyWith(color: Tokens.white)),
        backgroundColor: Tokens.ink,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
        ),
      ),
    );
}

/// Turns a mutation into a user-facing message.
///
/// A local save is not a failure and, when the server has no endpoint for the
/// collection yet, it is not an outage either — the item really is saved.
String mutationMessage(MutationResult result, {required String done}) =>
    switch (result) {
      MutationOk() => done,
      MutationLocal() => done,
      MutationFailed(:final error) => error.message,
    };

/// Helper so callers do not import [ApiError] just for the type check.
bool isOfflineError(Object? error) =>
    error is ApiError &&
    (error.code == 'offline' ||
        error.code == 'connection_lost' ||
        error.code == 'timeout');