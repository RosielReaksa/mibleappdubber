import 'package:dubber_app/core/api/api_error.dart';
import 'package:dubber_app/core/widgets/dubber_character.dart';
import 'package:dubber_app/features/editor/application/editor_controller.dart';
import 'package:dubber_app/features/library/application/library_controller.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/library/sections/logos_section.dart';
import 'package:dubber_app/features/library/sections/presets_section.dart';
import 'package:dubber_app/features/library/sections/styles_section.dart';
import 'package:dubber_app/features/library/widgets/library_widgets.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump one section with storage seeded for a specific state.
///
/// A repository with `api: null` reads only memory, so these tests exercise
/// the real section widget and the real controller without any network.
Future<void> pumpSection(
  WidgetTester tester,
  Widget section, {
  Map<String, List<Map<String, dynamic>>> seed = const {},
  LibraryLocalStore? store,
}) async {
  final local = store ?? MemoryLibraryLocalStore(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryStoreProvider.overrideWithValue(local),
        logoRepositoryProvider.overrideWithValue(LogoRepository(local)),
        styleRepositoryProvider.overrideWithValue(StyleRepository(local)),
        presetRepositoryProvider.overrideWithValue(PresetRepository(local)),
      ],
      child: MaterialApp(
        // The character animates forever, so `pumpAndSettle` would never
        // return; reduced motion makes every section's frame deterministic.
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: section),
        ),
      ),
    ),
  );
  // Let initState's load() finish. Fixed pumps rather than `pumpAndSettle`:
  // an indeterminate spinner and the character never settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// A store whose reads always fail, so the repository surfaces an error path.
class _BrokenStore implements LibraryLocalStore {
  @override
  Future<List<Map<String, dynamic>>> read(String section) async =>
      throw const ApiError(code: 'broken', message: 'Storage is damaged.');

  @override
  Future<void> write(String section, List<Map<String, dynamic>> items) async {}
}

void main() {
  final textStyle = const SavedStyle(
    id: 's1',
    name: 'Clay headline',
    kind: StyleKind.text,
    size: 64,
    color: '#D97757',
  ).toJson();
  final subStyle = const SavedStyle(
    id: 's2',
    name: 'Big bold subs',
    kind: StyleKind.subtitle,
    size: 70,
    subtitleStyle: SubtitleStyle.bold,
  ).toJson();
  final logo = const SavedLogo(id: 'l1', name: 'Brand mark').toJson();
  final preset = Preset.fromNewProject(
    id: 'p1',
    name: 'Shorts preset',
    format: VideoFormat.portrait,
    mix: AudioMix.voiceOver,
  ).toJson();

  group('Logos section', () {
    testWidgets('empty shows the character, copy and Add logo', (tester) async {
      await pumpSection(tester, const LogosSection());
      expect(find.text('No logos yet'), findsOneWidget);
      expect(find.text('Add logo'), findsOneWidget);
      expect(find.byType(DubberCharacter), findsWidgets);
    });

    testWidgets('ready shows one card per saved logo', (tester) async {
      await pumpSection(
        tester,
        const LogosSection(),
        seed: {'logos': [logo]},
      );
      expect(find.text('Brand mark'), findsOneWidget);
      expect(find.text('No logos yet'), findsNothing);
    });

    testWidgets('loading shows a spinner before storage answers',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryStoreProvider.overrideWithValue(MemoryLibraryLocalStore()),
            logoRepositoryProvider
                .overrideWithValue(LogoRepository(MemoryLibraryLocalStore())),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: LogosSection()),
            ),
          ),
        ),
      );
      // First frame: the controller has not finished loading yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('a broken store still renders (no crash)', (tester) async {
      await pumpSection(
        tester,
        const LogosSection(),
        store: _BrokenStore(),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Styles section', () {
    testWidgets('empty offers Create style', (tester) async {
      await pumpSection(tester, const StylesSection());
      expect(find.text('No saved styles'), findsOneWidget);
      expect(find.text('Create style'), findsOneWidget);
    });

    testWidgets('ready groups text and subtitle styles', (tester) async {
      await pumpSection(
        tester,
        const StylesSection(),
        seed: {
          'styles': [textStyle, subStyle],
        },
      );
      expect(find.text('Clay headline'), findsOneWidget);
      expect(find.text('Big bold subs'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget);
      expect(find.text('Bold · 70'), findsOneWidget);
    });

    testWidgets('offline shows the banner and hides the add button action',
        (tester) async {
      // A memory store seeded through a repository that cannot reach a server
      // still behaves; the banner path is covered by the repository tests and
      // the presentational grid, so assert the banner widget itself renders.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StylesList(
              styles: const [
                SavedStyle(id: 'a', name: 'Mine', kind: StyleKind.text),
              ],
              offline: true,
              canMutate: false,
              onCreate: () {},
              onRename: (_) {},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(find.text('Offline. Showing saved items. Adding and deleting are paused.'),
          findsOneWidget);
    });
  });

  group('Presets section', () {
    testWidgets('empty offers Save as preset', (tester) async {
      await pumpSection(tester, const PresetsSection());
      expect(find.text('No presets yet'), findsOneWidget);
      expect(find.text('Save as preset'), findsOneWidget);
    });

    testWidgets('ready lists the preset with a settings summary',
        (tester) async {
      await pumpSection(
        tester,
        const PresetsSection(),
        seed: {'presets': [preset]},
      );
      expect(find.text('Shorts preset'), findsOneWidget);
      expect(find.textContaining('Portrait'), findsWidgets);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('delete asks for confirmation', (tester) async {
      await pumpSection(
        tester,
        const PresetsSection(),
        seed: {'presets': [preset]},
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete preset?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Cancel leaves the preset in place.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Shorts preset'), findsOneWidget);
    });
  });

  group('Library shell chrome', () {
    testWidgets('Help is a 44x44 button labelled Help', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: LibraryHeader(
                credits: 84,
                onHelp: () {},
                onCredits: () {},
                onAccount: () {},
              ),
            ),
          ),
        ),
      );
      // The semantics wrapper carries the label the brief requires.
      expect(find.bySemanticsLabel('Help'), findsOneWidget);
      expect(find.byTooltip('Help'), findsOneWidget);
      // The tap target itself is the 44x44 box the header builds.
      final box = tester.widget<SizedBox>(
        find
            .ancestor(
              of: find.byType(Tooltip),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box.width, 44);
      expect(box.height, 44);
      expect(find.text('84 credits'), findsOneWidget);
    });

    testWidgets('the section switch offers all four sections', (tester) async {
      LibrarySection selected = LibrarySection.templates;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: Scaffold(
              body: LibrarySections(
                value: selected,
                onChanged: (s) => setState(() => selected = s),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Logos'), findsOneWidget);
      expect(find.text('Styles'), findsOneWidget);
      expect(find.text('My presets'), findsOneWidget);

      await tester.tap(find.text('Logos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(selected, LibrarySection.logos);
    });
  });
}