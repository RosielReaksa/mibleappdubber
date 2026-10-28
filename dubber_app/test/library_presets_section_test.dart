import 'package:dubber_app/features/library/application/library_controller.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/library/sections/presets_section.dart';
import 'package:dubber_app/features/library/widgets/library_widgets.dart';
import 'package:dubber_app/core/api/api_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dubber_app/features/projects/domain/models.dart';

void main() {
  test('preset serialization round-trips settings', () {
    final preset = Preset.fromNewProject(
      id: 'p1',
      name: 'Vertical',
      format: VideoFormat.portrait,
      mix: AudioMix.voiceOver,
      subtitlesOn: true,
      subtitleStyle: 'bold',
      fitMode: 'blur',
      fitBlur: 24,
      logoPosition: 'top_right',
    );
    expect(preset.template.format, VideoFormat.portrait);
    expect(preset.template.mix, AudioMix.voiceOver);
    final restored = Preset.fromJson(preset.toJson());
    expect(restored.id, preset.id);
    expect(restored.name, preset.name);
    expect(restored.template.format, preset.template.format);
    expect(restored.template.mix, preset.template.mix);
    expect(restored.template.subtitleStyle, 'bold');
    expect(restored.template.subtitlesOn, isTrue);
    expect(restored.template.fitMode, 'blur');
    expect(restored.template.fitBlur, 24);
    expect(restored.template.logoPosition, 'top_right');
  });

  test('presetsForChips sorts newest first and caps', () {
    final items = [
      _preset('old', 1),
      _preset('newest', 3),
      _preset('middle', 2),
    ];
    expect(presetsForChips(items, limit: 2).map((e) => e.name), ['newest', 'middle']);
  });

  testWidgets('loading state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: Scaffold(body: LibraryBody<Preset>(
      state: LibraryState<Preset>(), emptyTitle: 'No presets yet', emptyMessage: '', emptyAction: 'Save as preset', onAction: _noop,
      errorTitle: 'We could not load your presets', onRetry: _noop, builder: _builder,
    )))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_body(const LibraryState<Preset>(phase: LibraryPhase.empty)));
    expect(find.text('No presets yet'), findsOneWidget);
    expect(find.text('Save as preset'), findsOneWidget);
  });

  testWidgets('error state', (tester) async {
    await tester.pumpWidget(_body(const LibraryState<Preset>(phase: LibraryPhase.error, error: _TestApiError())));
    expect(find.text('We could not load your presets'), findsOneWidget);
  });

  testWidgets('ready section renders summary without null', (tester) async {
    final store = MemoryLibraryLocalStore({'presets': [_preset('p1', 1, mix: true).toJson()]});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryStoreProvider.overrideWithValue(store),
        presetRepositoryProvider.overrideWithValue(PresetRepository(store, null)),
      ],
      child: const MaterialApp(home: Scaffold(body: PresetsSection())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Landscape · Voice-over'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });
}

Preset _preset(String id, int createdAt, {bool mix = false}) => Preset.fromNewProject(
      id: 'preset_$createdAt',
      name: id,
      format: VideoFormat.landscape,
      mix: mix ? AudioMix.voiceOver : const AudioMix(),
    );

Widget _body(LibraryState<Preset> state) => MaterialApp(home: Scaffold(body: LibraryBody<Preset>(
      state: state,
      emptyTitle: 'No presets yet',
      emptyMessage: 'No presets available.',
      emptyAction: 'Save as preset',
      onAction: _noop,
      errorTitle: 'We could not load your presets',
      onRetry: _noop,
      builder: _builder,
    )));

Widget _builder(BuildContext context, List<Preset> presets) => PresetsList(
      presets: presets, offline: false, canMutate: true, onSave: _noop, onRename: (_) {}, onDelete: (_) {},
    );

void _noop() {}

class _TestApiError extends ApiError {
  const _TestApiError() : super(code: 'test', message: 'Test error');
}
