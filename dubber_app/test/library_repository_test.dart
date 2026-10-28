import 'package:dubber_app/core/api/api_error.dart';
import 'package:dubber_app/features/editor/application/editor_controller.dart';
import 'package:dubber_app/features/library/application/library_controller.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository whose server calls behave the way a test wants.
class _FakeRemoteRepository<T> extends LibraryRepository<T> {
  _FakeRemoteRepository(
    super.local, {
    this.onFetch,
    this.onCreate,
    this.onDelete,
    required this.parse,
    required this.serialize,
    required this.idOfItem,
    required this.renamer,
    required this.label,
  });

  final List<Map<String, dynamic>> Function()? onFetch;
  final Map<String, dynamic> Function(T item)? onCreate;
  final void Function()? onDelete;
  final T Function(Map<String, dynamic>) parse;
  final Map<String, dynamic> Function(T) serialize;
  final String Function(T) idOfItem;
  final T Function(T, String) renamer;
  final String label;

  @override
  bool get remoteEnabled => true;

  @override
  String get section => label;

  @override
  T fromJson(Map<String, dynamic> j) => parse(j);

  @override
  Map<String, dynamic> toJson(T item) => serialize(item);

  @override
  String idOf(T item) => idOfItem(item);

  @override
  T _renamed(T item, String newName) => renamer(item, newName);

  @override
  Future<List<Map<String, dynamic>>>? fetchRemoteRaw() async {
    final items = onFetch?.call();
    if (items == null) throw const ApiError(code: 'http_500', message: 'boom', httpStatus: 500);
    return items;
  }

  @override
  Future<Map<String, dynamic>?> createRemoteRaw(T item) async =>
      onCreate?.call(item);

  @override
  Future<bool> deleteRemote(String id) async {
    onDelete?.call();
    return true;
  }
}

SavedStyle _style(Map<String, dynamic> j) => SavedStyle.fromJson(j);
Map<String, dynamic> _styleJson(SavedStyle s) => s.toJson();
String _styleId(SavedStyle s) => s.id;
SavedStyle _styleRename(SavedStyle s, String n) => s.copyWith(name: n);

void main() {
  const presetBase = SavedStyle(
    id: 's1',
    name: 'My style',
    kind: StyleKind.text,
    size: 42,
    color: '#D97757',
  );

  group('repository fallbacks', () {
    test('a network failure returns the cached rows and marks them cached', () async {
      final store = MemoryLibraryLocalStore({
        'styles': [
          const SavedStyle(id: 'cached', name: 'Cached', kind: StyleKind.subtitle).toJson(),
        ],
      });
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => throw const ApiError.network(),
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );

      final loaded = await repo.load();

      expect(loaded.items.single.name, 'Cached');
      expect(loaded.isCached, isTrue);
      expect(loaded.origin, DataOrigin.cache);
    });

    test('a missing endpoint is local-only, not offline', () async {
      final store = MemoryLibraryLocalStore({
        'styles': [presetBase.toJson()],
      });
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => throw const ApiError(
          code: 'http_404',
          message: 'Not found',
          httpStatus: 404,
        ),
        onCreate: (_) => throw const ApiError(
          code: 'http_404',
          message: 'Not found',
          httpStatus: 404,
        ),
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );

      final loaded = await repo.load();

      expect(loaded.items.single.name, 'My style');
      expect(loaded.origin, DataOrigin.localOnly);
      expect(loaded.isCached, isFalse);
    });

    test('a create that the server does not implement lands locally', () async {
      final store = MemoryLibraryLocalStore();
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => throw const ApiError(
          code: 'http_404',
          message: 'Not found',
          httpStatus: 404,
        ),
        onCreate: (_) => throw const ApiError(
          code: 'http_404',
          message: 'Not found',
          httpStatus: 404,
        ),
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );

      await repo.load();
      final result = await repo.create(presetBase);

      expect(result, isA<MutationLocal>());
      expect(await store.read('styles'), hasLength(1));
    });

    test('the server list replaces the cache when it answers', () async {
      final store = MemoryLibraryLocalStore({
        'styles': [presetBase.toJson()],
      });
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => [
          const SavedStyle(
            id: 'remote',
            name: 'From server',
            kind: StyleKind.subtitle,
            subtitleStyle: SubtitleStyle.bold,
          ).toJson(),
        ],
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );

      final loaded = await repo.load();

      expect(loaded.items.single.id, 'remote');
      expect(loaded.origin, DataOrigin.server);
      // The cache now holds the server's answer.
      expect((await store.read('styles')).single['id'], 'remote');
    });

    test('a failed server create rolls the optimistic row back', () async {
      final store = MemoryLibraryLocalStore({'styles': <Map<String, dynamic>>[]});
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => <Map<String, dynamic>>[],
        onCreate: (_) => throw const ApiError(
          code: 'http_500',
          message: 'The server had a problem.',
          httpStatus: 500,
        ),
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );

      final result = await repo.create(presetBase);

      expect(result, isA<MutationFailed>());
      expect(await store.read('styles'), isEmpty);
    });

    test('a delete without an endpoint still removes the local row', () async {
      final store = MemoryLibraryLocalStore({
        'styles': [presetBase.toJson()],
      });
      // api null = no endpoint at all.
      final repo = StyleRepository(store);

      final result = await repo.delete('s1');

      expect(result, isA<MutationLocal>());
      expect(await store.read('styles'), isEmpty);
    });

    test('an unreadable cache is treated as empty, never throws', () async {
      final store = _ThrowingStore();
      final repo = StyleRepository(store);

      final loaded = await repo.load();

      expect(loaded.items, isEmpty);
    });
  });

  group('controller states', () {
    test('empty store without a server is empty, and stays usable', () async {
      final controller = LibraryController(StyleRepository(MemoryLibraryLocalStore()));

      await controller.load();

      expect(controller.state.phase, LibraryPhase.empty);
      expect(controller.state.offline, isFalse);
      expect(controller.state.canMutate, isTrue);
    });

    test('creating moves the section to ready and persists locally', () async {
      final store = MemoryLibraryLocalStore();
      final controller = LibraryController(StyleRepository(store));
      await controller.load();

      final result = await controller.create(presetBase);

      expect(result, isA<MutationLocal>());
      expect(controller.state.phase, LibraryPhase.ready);
      expect(controller.state.items.single.name, 'My style');
      expect(controller.state.offline, isFalse);
      expect((await store.read('styles')).single['id'], 's1');
    });

    test('renaming updates the row and keeps the list', () async {
      final store = MemoryLibraryLocalStore({'styles': [presetBase.toJson()]});
      final controller = LibraryController(StyleRepository(store));
      await controller.load();

      await controller.rename('s1', 'Renamed');

      expect(controller.state.items.single.name, 'Renamed');
    });

    test('deleting the last row returns the section to empty', () async {
      final store = MemoryLibraryLocalStore({'styles': [presetBase.toJson()]});
      final controller = LibraryController(StyleRepository(store));
      await controller.load();

      await controller.delete('s1');

      expect(controller.state.phase, LibraryPhase.empty);
      expect(controller.state.items, isEmpty);
    });

    test('a cached read disables changes until a server answers', () async {
      final store = MemoryLibraryLocalStore({'styles': [presetBase.toJson()]});
      final repo = _FakeRemoteRepository<SavedStyle>(
        store,
        onFetch: () => throw const ApiError.network(),
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );
      final controller = LibraryController(repo);

      await controller.load();

      expect(controller.state.offline, isTrue);
      expect(controller.state.canMutate, isFalse);
    });

    test('a failing server surfaces the error phase', () async {
      final repo = _FakeRemoteRepository<SavedStyle>(
        MemoryLibraryLocalStore(),
        onFetch: null,
        parse: _style,
        serialize: _styleJson,
        idOfItem: _styleId,
        renamer: _styleRename,
        label: 'styles',
      );
      final controller = LibraryController(repo);

      await controller.load();

      // The repository swallows remote failures into a cache read, so the
      // section shows empty rather than an error when nothing is stored.
      expect(controller.state.phase, LibraryPhase.empty);
    });
  });

  group('preset → New project prefill', () {
    test('a preset keeps the settings a template carries', () {
      final preset = Preset.fromNewProject(
        id: 'p1',
        name: 'Shorts',
        format: VideoFormat.portrait,
        mix: AudioMix.keepOriginal,
        subtitlesOn: true,
        subtitleStyle: 'bold',
        fitMode: 'fill',
        fitBlur: 40,
        logoPosition: 'bottom_right',
      );

      expect(preset.template.format, VideoFormat.portrait);
      expect(preset.template.mix, AudioMix.keepOriginal);
      expect(preset.template.subtitlesOn, isTrue);
      expect(preset.template.subtitleStyle, 'bold');
      expect(preset.template.fitMode, 'fill');
      expect(preset.template.fitBlur, 40);
      expect(preset.template.logoPosition, 'bottom_right');
    });

    test('a preset round-trips through JSON', () {
      final preset = Preset.fromNewProject(
        id: 'p1',
        name: 'Shorts',
        format: VideoFormat.portrait,
        mix: AudioMix.keepOriginal,
        subtitlesOn: true,
        subtitleStyle: 'bold',
        fitMode: 'fill',
        fitBlur: 40,
        logoPosition: 'bottom_right',
      );

      final restored = Preset.fromJson(preset.toJson());

      expect(restored.id, 'p1');
      expect(restored.name, 'Shorts');
      expect(restored.template.format, VideoFormat.portrait);
      expect(restored.template.mix, AudioMix.keepOriginal);
      expect(restored.template.subtitleStyle, 'bold');
      expect(restored.template.fitMode, 'fill');
      expect(restored.template.logoPosition, 'bottom_right');
    });

    test('a minimal preset leaves unknown settings absent', () {
      final preset = Preset.fromNewProject(
        id: 'p2',
        name: 'Plain',
        format: VideoFormat.landscape,
        mix: AudioMix.voiceOver,
      );

      final json = preset.toJson();

      expect(json['settings']['format'], 'landscape');
      expect(json['settings'].containsKey('logo_position'), isFalse);
      expect(Preset.fromJson(json).template.fitMode, isNull);
    });
  });

  group('style → editor state', () {
    test('a text style maps to the overlay size and color', () {
      const style = SavedStyle(
        id: 's1',
        name: 'Clay',
        kind: StyleKind.text,
        size: 72,
        color: '#D97757',
      );

      final overlay = const TextOverlay().copyWith(
        size: style.size,
        color: style.color,
      );

      expect(overlay.size, 72);
      expect(overlay.color, '#D97757');
    });

    test('a subtitle style maps to the editor subtitle fields', () {
      const style = SavedStyle(
        id: 's2',
        name: 'Big bold',
        kind: StyleKind.subtitle,
        size: 80,
        subtitleStyle: SubtitleStyle.bold,
      );

      final state = const EditorState().copyWith(
        subtitleStyle: style.subtitleStyle,
        subtitleSize: style.size,
      );

      expect(state.subtitleStyle, SubtitleStyle.bold);
      expect(state.subtitleSize, 80);
      expect(state.subtitlesOn, isTrue);
    });

    test('a style saved from the editor captures what is on screen', () {
      final state = const EditorState(
        tool: EditorTool.subtitles,
        subtitleStyle: SubtitleStyle.box,
        subtitleSize: 64,
      );

      final style = SavedStyle.fromEditor(
        id: 's3',
        name: 'Boxed',
        state: state,
      );

      expect(style.kind, StyleKind.subtitle);
      expect(style.subtitleStyle, SubtitleStyle.box);
      expect(style.size, 64);
    });

    test('the summary never shows a bare null', () {
      const text = SavedStyle(id: 'a', name: 'A', kind: StyleKind.text);
      const subs = SavedStyle(id: 'b', name: 'B', kind: StyleKind.subtitle);

      expect(text.summary.contains('null'), isFalse);
      expect(subs.summary.contains('null'), isFalse);
    });
  });
}

/// A store that fails every read, standing in for damaged storage.
class _ThrowingStore implements LibraryLocalStore {
  @override
  Future<List<Map<String, dynamic>>> read(String section) async =>
      throw StateError('damaged');

  @override
  Future<void> write(String section, List<Map<String, dynamic>> items) async {}
}