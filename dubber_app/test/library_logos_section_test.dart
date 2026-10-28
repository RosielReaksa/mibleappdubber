import 'package:dubber_app/features/library/application/library_controller.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/library/sections/logos_section.dart';
import 'package:dubber_app/features/library/widgets/library_widgets.dart';
import 'package:dubber_app/core/api/api_error.dart';
import 'package:dubber_app/core/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading spinner', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: LogosSection()))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows empty state and add logo action', (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No logos yet'), findsOneWidget);
    expect(find.text('Add logo'), findsOneWidget);
  });

  testWidgets('shows saved logos in the grid', (tester) async {
    await tester.pumpWidget(_harness(const [SavedLogo(id: '1', name: 'Brand'), SavedLogo(id: '2', name: 'Watermark')]));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Watermark'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('shows error state and retry affordance', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [logoLibraryProvider.overrideWith((ref) => _ErrorController())],
      child: const MaterialApp(home: Scaffold(body: LogosSection())),
    ));
    await tester.pump();
    expect(find.text('We could not load your logos'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offline grid shows banner and disables add and delete', (tester) async {
    var addCalled = false;
    var deleteCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LogosGrid(
        logos: const [SavedLogo(id: '1', name: 'Brand')],
        offline: true,
        canMutate: false,
        onAdd: () => addCalled = true,
        onDelete: (_) => deleteCalled = true,
      )),
    ));
    expect(find.byType(OfflineBanner), findsOneWidget);
    final add = tester.widget<SecondaryButton>(find.byType(SecondaryButton));
    expect(add.onPressed, isNull);
    expect(find.byTooltip('Logo actions for Brand'), findsOneWidget);
    expect(addCalled, isFalse);
    expect(deleteCalled, isFalse);
  });
}

Widget _harness(List<SavedLogo> logos) {
  final store = MemoryLibraryLocalStore({'logos': logos.map((e) => e.toJson()).toList()});
  return ProviderScope(
    overrides: [
      libraryStoreProvider.overrideWithValue(store),
      logoRepositoryProvider.overrideWithValue(LogoRepository(store, null)),
    ],
    child: const MaterialApp(home: Scaffold(body: LogosSection())),
  );
}

class _ErrorController extends LibraryController<SavedLogo> {
  _ErrorController() : super(LogoRepository(MemoryLibraryLocalStore(), null));

  @override
  Future<void> load() async {
    state = LibraryState(phase: LibraryPhase.error, error: const _TestApiError());
  }
}

class _TestApiError extends ApiError {
  const _TestApiError() : super(code: 'test', message: 'Test error');
}
