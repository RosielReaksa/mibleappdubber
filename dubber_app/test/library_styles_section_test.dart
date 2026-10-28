import 'package:dubber_app/core/api/api_error.dart';
import 'package:dubber_app/core/widgets/app_widgets.dart';
import 'package:dubber_app/features/library/application/library_controller.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/editor/application/editor_controller.dart';
import 'package:dubber_app/features/library/sections/styles_section.dart';
import 'package:dubber_app/features/library/widgets/library_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state offers create style', (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No saved styles'), findsOneWidget);
    expect(find.text('Create style'), findsOneWidget);
  });

  testWidgets('ready state groups text and subtitle styles with summaries', (tester) async {
    await tester.pumpWidget(_harness(const [
      SavedStyle(id: 't', name: 'Headline', kind: StyleKind.text, size: 60, color: '#FFFFFF'),
      SavedStyle(id: 's', name: 'Caption', kind: StyleKind.subtitle, size: 55, subtitleStyle: SubtitleStyle.bold),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('#FFFFFF · 60'), findsOneWidget);
    expect(find.text('Bold · 55'), findsOneWidget);
  });

  testWidgets('error state offers retry', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [styleLibraryProvider.overrideWith((ref) => _ErrorController())], child: const MaterialApp(home: Scaffold(body: StylesSection()))));
    await tester.pump();
    expect(find.text('We could not load your styles'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offline list shows banner and disables create', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StylesList(styles: const [SavedStyle(id: 't', name: 'Headline', kind: StyleKind.text)], offline: true, canMutate: false, onCreate: () {}, onRename: (_) {}, onDelete: (_) {}))));
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(tester.widget<SecondaryButton>(find.byType(SecondaryButton)).onPressed, isNull);
  });

  test('subtitle mapping returns saved editor style', () {
    const style = SavedStyle(id: 's', name: 'Box', kind: StyleKind.subtitle, subtitleStyle: SubtitleStyle.box);
    expect(subtitleStyleFor(style), SubtitleStyle.box);
  });
}

Widget _harness(List<SavedStyle> styles) {
  final store = MemoryLibraryLocalStore({'styles': styles.map((e) => e.toJson()).toList()});
  return ProviderScope(overrides: [libraryStoreProvider.overrideWithValue(store), styleRepositoryProvider.overrideWithValue(StyleRepository(store, null))], child: const MaterialApp(home: Scaffold(body: StylesSection())));
}

class _ErrorController extends LibraryController<SavedStyle> {
  _ErrorController() : super(StyleRepository(MemoryLibraryLocalStore(), null));
  @override
  Future<void> load() async { state = LibraryState(phase: LibraryPhase.error, error: const ApiError(code: 'test', message: 'Test error')); }
}
