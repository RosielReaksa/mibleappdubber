import 'package:dio/dio.dart';
import 'package:dubber_app/core/api/api_client.dart';
import 'package:dubber_app/features/library/data/library_local_store.dart';
import 'package:dubber_app/features/library/data/library_repository.dart';
import 'package:dubber_app/features/library/domain/library_models.dart';
import 'package:dubber_app/features/projects/data/dubber_api.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the real repository against the demo server on localhost.
///
/// Skipped unless `DUBBER_LIVE=1`, so the normal suite stays hermetic.
void main() {
  const live = bool.fromEnvironment('DUBBER_LIVE');

  setUp(() {
    // The client's interceptor reads the token from this store, exactly as
    // it does in the app.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('create against a server without /presets saves locally', () async {
    if (!live) {
      markTestSkipped('Set DUBBER_LIVE=1 with the demo server running.');
      return;
    }
    final store = TokenStore();
    final client = ApiClient(baseUrl: 'http://127.0.0.1:8099/v1', tokens: store);
    final api = DubberApi(client);
    final tokens = await api.login(
      email: 'demo@dubber.app',
      password: 'password123',
    );
    await store.save(access: tokens.access, refresh: tokens.refresh);

    final repo = PresetRepository(MemoryLibraryLocalStore(), api);
    final loaded = await repo.load();
    // ignore: avoid_print
    print('load origin: ${loaded.origin} items=${loaded.items.length}');

    final preset = Preset.fromNewProject(
      id: 'p_test',
      name: 'Test preset',
      format: VideoFormat.portrait,
      mix: AudioMix.voiceOver,
    );
    final result = await repo.create(preset);
    // ignore: avoid_print
    print('create result: $result');

    expect(result, isA<MutationLocal>());
    expect((await repo.readLocal()).single.name, 'Test preset');
  });

  test('the raw create call surfaces its ApiError', () async {
    if (!live) {
      markTestSkipped('Set DUBBER_LIVE=1 with the demo server running.');
      return;
    }
    final store = TokenStore();
    final client = ApiClient(baseUrl: 'http://127.0.0.1:8099/v1', tokens: store);
    final tokens = await DubberApi(client).login(
      email: 'demo@dubber.app',
      password: 'password123',
    );
    await store.save(access: tokens.access, refresh: tokens.refresh);

    try {
      await client.dio.post<Map<String, dynamic>>(
        '/presets',
        data: {'name': 'x', 'settings': {}},
      );
      fail('expected an error');
    } catch (e) {
      final mapped = ApiClient.toApiError(e);
      // ignore: avoid_print
      print('mapped: code=${mapped.code} status=${mapped.httpStatus} '
          'message=${mapped.message}');
      expect(mapped.httpStatus, 404);
    }
  });
}