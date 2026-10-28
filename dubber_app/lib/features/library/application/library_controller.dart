import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_error.dart';
import '../data/library_local_store.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';

/// The four states every Library section can be in.
enum LibraryPhase {
  /// Reading storage and the server.
  loading,

  /// Loaded and not empty.
  ready,

  /// Loaded, but the user has nothing saved yet.
  empty,

  /// The server failed and there is nothing cached to show.
  error,
}

/// State shared by every Library section.
///
/// [items] stays populated in the offline case so the screen can show cached
/// rows while create/delete are disabled.
class LibraryState<T> {
  const LibraryState({
    this.phase = LibraryPhase.loading,
    this.items = const [],
    this.error,
    this.offline = false,
    this.busy = false,
  });

  final LibraryPhase phase;
  final List<T> items;
  final ApiError? error;

  /// True when the list came from the local store because the server was
  /// unreachable. Creating and deleting are disabled in this state.
  final bool offline;

  /// True while a create/rename/delete is in flight.
  final bool busy;

  bool get canMutate => !offline && !busy;

  LibraryState<T> copyWith({
    LibraryPhase? phase,
    List<T>? items,
    ApiError? error,
    bool clearError = false,
    bool? offline,
    bool? busy,
  }) =>
      LibraryState<T>(
        phase: phase ?? this.phase,
        items: items ?? this.items,
        error: clearError ? null : (error ?? this.error),
        offline: offline ?? this.offline,
        busy: busy ?? this.busy,
      );
}

/// Loads one section and applies creates, renames and deletes.
class LibraryController<T> extends StateNotifier<LibraryState<T>> {
  LibraryController(this._repo) : super(const LibraryState());

  final LibraryRepository<T> _repo;

  /// Remembers whether the last load came from the cache, so an offline
  /// screen keeps its banner after a mutation.
  bool _cached = false;

  Future<void> load() async {
    state = state.copyWith(phase: LibraryPhase.loading, clearError: true);
    try {
      final loaded = await _repo.load();
      _cached = loaded.isCached;
      state = LibraryState(
        phase: loaded.items.isEmpty ? LibraryPhase.empty : LibraryPhase.ready,
        items: loaded.items,
        offline: loaded.isCached,
      );
    } catch (e) {
      state = LibraryState(
        phase: LibraryPhase.error,
        error: e is ApiError ? e : const ApiError.unknown(),
      );
    }
  }

  /// Adds [item] and returns how it went, so the screen can show a message.
  Future<MutationResult> create(T item) async {
    final previous = state.items;
    // Optimistic: the new row appears immediately.
    state = state.copyWith(
      items: [...previous, item],
      phase: LibraryPhase.ready,
      busy: true,
    );
    final result = await _repo.create(item);
    return _settle(result, previous);
  }

  Future<MutationResult> rename(String id, String name) async {
    final previous = state.items;
    state = state.copyWith(busy: true);
    final result = await _repo.rename(id, name);
    // Re-read the store: the repository applied the new name there, and a
    // failure has already restored the old rows.
    return _settle(result, previous);
  }

  Future<MutationResult> delete(String id) async {
    final previous = state.items;
    state = state.copyWith(
      items: [
        for (final item in previous)
          if (_repo.idOf(item) != id) item,
      ],
      busy: true,
    );
    final result = await _repo.delete(id);
    return _settle(result, previous);
  }

  Future<MutationResult> _settle(
    MutationResult result,
    List<T> previous,
  ) async {
    switch (result) {
      case MutationOk():
      case MutationLocal():
        final items = await _repo.readLocal();
        state = LibraryState(
          phase: items.isEmpty ? LibraryPhase.empty : LibraryPhase.ready,
          items: items,
          // A local save with no endpoint behind it is normal operation, not
          // an outage; only a genuine cached read shows the offline banner.
          offline: _cached,
          busy: false,
        );
      case MutationFailed(:final error):
        state = state.copyWith(
          items: previous,
          phase: previous.isEmpty ? LibraryPhase.empty : LibraryPhase.ready,
          error: error,
          busy: false,
        );
    }
    return result;
  }
}

// ── Providers ─────────────────────────────────────────────────────────────

final libraryStoreProvider =
    Provider<LibraryLocalStore>((ref) => PrefsLibraryLocalStore());

final logoRepositoryProvider = Provider<LogoRepository>(
  (ref) => LogoRepository(ref.watch(libraryStoreProvider), ref.watch(apiProvider)),
);

final styleRepositoryProvider = Provider<StyleRepository>(
  (ref) => StyleRepository(ref.watch(libraryStoreProvider), ref.watch(apiProvider)),
);

final presetRepositoryProvider = Provider<PresetRepository>(
  (ref) => PresetRepository(ref.watch(libraryStoreProvider), ref.watch(apiProvider)),
);

final logoLibraryProvider =
    StateNotifierProvider<LibraryController<SavedLogo>, LibraryState<SavedLogo>>(
  (ref) => LibraryController(ref.watch(logoRepositoryProvider)),
);

final styleLibraryProvider = StateNotifierProvider<LibraryController<SavedStyle>,
    LibraryState<SavedStyle>>(
  (ref) => LibraryController(ref.watch(styleRepositoryProvider)),
);

final presetLibraryProvider =
    StateNotifierProvider<LibraryController<Preset>, LibraryState<Preset>>(
  (ref) => LibraryController(ref.watch(presetRepositoryProvider)),
);