import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/tokens.dart';
import '../auth/application/auth_controller.dart';
import 'sections/logos_section.dart';
import 'sections/presets_section.dart';
import 'sections/styles_section.dart';
import 'sections/templates_section.dart';
import 'widgets/library_widgets.dart';

/// The Library tab: Templates, Logos, Styles, My presets.
///
/// This shell owns the header (title, Help, credits, avatar), the section
/// switch, and which section body is on screen. Each body keeps its own state
/// so switching sections never reloads the others.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.section = LibrarySection.templates});

  /// Which section opens first; `?section=logos` deep-links to Logos.
  final LibrarySection section;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late LibrarySection _section = widget.section;

  @override
  Widget build(BuildContext context) {
    final credits = ref.watch(authControllerProvider).session?.credits;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LibraryHeader(
              credits: credits,
              onHelp: () => context.push('/learn'),
              onCredits: () => context.push('/account/credits'),
              onAccount: () => context.push('/account'),
            ),
            LibrarySections(
              value: _section,
              onChanged: (s) => setState(() => _section = s),
            ),
            Expanded(
              child: IndexedStack(
                index: _section.index,
                children: const [
                  TemplatesSection(),
                  LogosSection(),
                  StylesSection(),
                  PresetsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}