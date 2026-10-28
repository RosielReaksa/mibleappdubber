import 'package:meta/meta.dart';

import '../../../core/api/api_error.dart';
import '../../projects/data/dubber_api.dart';
import '../domain/library_models.dart';
import 'library_local_store.dart';

/// Where a screen's data came from, so it can show an offline banner.
enum DataOrigin {
  /// Straight from the server.
  server,

  /// The server could not be reached, so the local copy is on screen.
  cache,

  /// The server has no endpoint for this collection yet; the local copy is
  /// the source of truth and behaves normally (no offline banner).
  localOnly,
}

/// A loaded list plus where it came from.
class Loaded<T> {
  const Loaded(this.items, this.origin);

  final List<T> items;
  final DataOrigin origin;

  /// True only when the device could not reach a server that should have it.
  bool get isCached => origin == DataOrigin.cache;
}

/// What a create/rename/delete attempt produced.
sealed class MutationResult {
  const MutationResult();
}

final class MutationOk extends MutationResult {
  const MutationOk();
}

/// The item was saved locally because the server is unreachable or the
/// endpoint does not exist yet.
final class MutationLocal extends MutationResult {
  const MutationLocal();
}

final class MutationFailed extends MutationResult {
  const MutationFailed(this.error);
  final ApiError error;
}

/// Base class for the three Library repositories.
///
/// Every repository works the same way: try the server, fall back to the local
/// store, and persist whatever the server returns. When the endpoint does not
/// exist (or the device is offline) the local copy is authoritative, so the
/// app behaves identically with or without a server implementation.
abstract class LibraryRepository<T> {
  LibraryRepository(this.local, [this.api]);

  final LibraryLocalStore local;

  /// Null in tests, and in builds that have no server endpoints yet.
  final DubberApi? api;

  /// Key used in the local store.
  String get section;

  T fromJson(Map<String, dynamic> j);
  Map<String, dynamic> toJson(T item);
  String idOf(T item);

  /// Server read, as raw JSON so the base class owns the mapping.
  Future<List<Map<String, dynamic>>>? fetchRemoteRaw() => null;

  /// Server create. Returns the saved row, or null when not supported.
  Future<Map<String, dynamic>?> createRemoteRaw(T item) async => null;

  /// Server rename. Returns false when the endpoint is absent.
  Future<bool> renameRemote(String id, String newName) async => false;

  /// Server delete. Returns false when the endpoint is absent.
  Future<bool> deleteRemote(String id) async => false;

  /// Reads the local copy. A damaged store reads as empty rather than throwing,
  /// so storage can never take a screen down.
  Future<List<T>> readLocal() async {
    try {
      return (await local.read(section)).map(fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeLocal(List<T> items) =>
      local.write(section, items.map(toJson).toList());

  /// True when the server has never answered for this section.
  ///
  /// The first failed read flips it off for the session, so the UI does not
  /// pretend to be online after a 404 from an endpoint that does not exist.
  bool _remoteDown = false;

  /// Whether mutations should be attempted against the server.
  bool get remoteAvailable => remoteEnabled && !_remoteDown;

  /// Whether this repository has a server behind it at all. Tests override it
  /// so a fake server can be exercised without constructing an HTTP client.
  @protected
  bool get remoteEnabled => api != null;

  /// Whether a *write* should be attempted.
  ///
  /// A read only proves that `GET` is missing; the create/rename/delete
  /// endpoints may still exist, so they are attempted once even after a read
  /// failed. A write that answers 404/405/501 turns them off for the session.
  bool get _canReachServer => remoteEnabled;

  /// Cache first, then the server; the server's answer replaces the cache.
  ///
  /// Returns cached items with [DataOrigin.cache] when the server cannot be
  /// reached, so the screen can show what it has instead of an empty state.
  Future<Loaded<T>> load() async {
    final cached = await readLocal();
    final call = fetchRemoteRaw();
    if (call == null || _remoteDown) {
      return Loaded(cached, DataOrigin.localOnly);
    }
    try {
      final fresh = (await call).map(fromJson).toList();
      await _writeLocal(fresh);
      _remoteDown = false;
      return Loaded(fresh, DataOrigin.server);
    } catch (e) {
      final error = e is ApiError ? e : const ApiError.unknown();
      if (_meansAbsent(error)) {
        // No endpoint yet: local storage is authoritative, not "offline".
        _remoteDown = true;
        return Loaded(cached, DataOrigin.localOnly);
      }
      return Loaded(cached, DataOrigin.cache);
    }
  }

  /// Adds [item]. Local first so the UI updates immediately, then the server.
  Future<MutationResult> create(T item) async {
    final items = [...await readLocal(), item];
    await _writeLocal(items);
    if (!_canReachServer) return const MutationLocal();

    try {
      final saved = await createRemoteRaw(item);
      if (saved == null) return const MutationLocal();
      final parsed = fromJson(saved);
      // The server may assign its own id; keep its row, drop the optimistic one.
      await _writeLocal([
        for (final existing in items)
          if (idOf(existing) != idOf(item)) existing,
        parsed,
      ]);
      return const MutationOk();
    } catch (e) {
      final error = e is ApiError ? e : const ApiError.unknown();
      if (_meansAbsent(error)) {
        _remoteDown = true;
        return const MutationLocal();
      }
      // Roll the optimistic add back so local and server agree.
      await _writeLocal([
        for (final existing in items)
          if (idOf(existing) != idOf(item)) existing,
      ]);
      return MutationFailed(error);
    }
  }

  /// Renames [id]. Local first; the server is told afterwards.
  Future<MutationResult> rename(String id, String newName) async {
    final before = await readLocal();
    await _writeLocal([
      for (final item in before)
        if (idOf(item) == id) _renamed(item, newName) else item,
    ]);
    if (!_canReachServer) return const MutationLocal();

    try {
      await renameRemote(id, newName);
      return const MutationOk();
    } catch (e) {
      final error = e is ApiError ? e : const ApiError.unknown();
      if (_meansAbsent(error)) {
        _remoteDown = true;
        return const MutationLocal();
      }
      await _writeLocal(before);
      return MutationFailed(error);
    }
  }

  /// Deletes [id]. Local first; a server failure restores the row.
  Future<MutationResult> delete(String id) async {
    final before = await readLocal();
    await _writeLocal([
      for (final item in before)
        if (idOf(item) != id) item,
    ]);
    if (!_canReachServer) return const MutationLocal();

    try {
      await deleteRemote(id);
      return const MutationOk();
    } catch (e) {
      final error = e is ApiError ? e : const ApiError.unknown();
      if (_meansAbsent(error)) {
        _remoteDown = true;
        return const MutationLocal();
      }
      await _writeLocal(before);
      return MutationFailed(error);
    }
  }

  /// How a rename is applied to one item.
  T _renamed(T item, String newName);

  /// A missing endpoint is not a user-facing failure; it means the server has
  /// not shipped this feature yet and local storage is the source of truth.
  static bool _meansAbsent(ApiError error) =>
      error.httpStatus == 404 ||
      error.httpStatus == 405 ||
      error.httpStatus == 501 ||
      error.code == 'http_404' ||
      error.code == 'http_405' ||
      error.code == 'http_501';

  /// True when the error means the device has no network, as opposed to the
  /// server rejecting the request. Used by the controller to pick the
  /// offline banner copy.
  static bool isOffline(Object? error) {
    if (error is! ApiError) return false;
    return error.code == 'offline' ||
        error.code == 'connection_lost' ||
        error.code == 'timeout';
  }
}

/// Saved logos.
class LogoRepository extends LibraryRepository<SavedLogo> {
  LogoRepository(super.local, [super.api]);

  @override
  String get section => 'logos';

  @override
  SavedLogo fromJson(Map<String, dynamic> j) => SavedLogo.fromJson(j);

  @override
  Map<String, dynamic> toJson(SavedLogo item) => item.toJson();

  @override
  String idOf(SavedLogo item) => item.id;

  @override
  SavedLogo _renamed(SavedLogo item, String newName) =>
      item.copyWith(name: newName);

  @override
  Future<List<Map<String, dynamic>>>? fetchRemoteRaw() =>
      api == null ? null : api!.libraryLogos();

  @override
  Future<Map<String, dynamic>?> createRemoteRaw(SavedLogo item) async =>
      api == null ? null : await api!.createLibraryLogoRecord(item);

  @override
  Future<bool> renameRemote(String id, String newName) async {
    if (api == null) return false;
    await api!.updateLibraryLogo(id, itemName: newName);
    return true;
  }

  @override
  Future<bool> deleteRemote(String id) async {
    if (api == null) return false;
    await api!.deleteLibraryLogo(id);
    return true;
  }
}

/// Saved text and subtitle styles.
class StyleRepository extends LibraryRepository<SavedStyle> {
  StyleRepository(super.local, [super.api]);

  @override
  String get section => 'styles';

  @override
  SavedStyle fromJson(Map<String, dynamic> j) => SavedStyle.fromJson(j);

  @override
  Map<String, dynamic> toJson(SavedStyle item) => item.toJson();

  @override
  String idOf(SavedStyle item) => item.id;

  @override
  SavedStyle _renamed(SavedStyle item, String newName) =>
      item.copyWith(name: newName);

  @override
  Future<List<Map<String, dynamic>>>? fetchRemoteRaw() =>
      api == null ? null : api!.libraryStyles();

  @override
  Future<Map<String, dynamic>?> createRemoteRaw(SavedStyle item) async =>
      api == null ? null : await api!.createLibraryStyle(item.toJson());

  @override
  Future<bool> renameRemote(String id, String newName) async {
    if (api == null) return false;
    await api!.updateLibraryStyle(id, {'name': newName});
    return true;
  }

  @override
  Future<bool> deleteRemote(String id) async {
    if (api == null) return false;
    await api!.deleteLibraryStyle(id);
    return true;
  }
}

/// The user's own templates.
class PresetRepository extends LibraryRepository<Preset> {
  PresetRepository(super.local, [super.api]);

  @override
  String get section => 'presets';

  @override
  Preset fromJson(Map<String, dynamic> j) => Preset.fromJson(j);

  @override
  Map<String, dynamic> toJson(Preset item) => item.toJson();

  @override
  String idOf(Preset item) => item.id;

  @override
  Preset _renamed(Preset item, String newName) => item.copyWith(name: newName);

  @override
  Future<List<Map<String, dynamic>>>? fetchRemoteRaw() =>
      api == null ? null : api!.libraryPresets();

  @override
  Future<Map<String, dynamic>?> createRemoteRaw(Preset item) async =>
      api == null ? null : await api!.createLibraryPreset(item.toJson());

  @override
  Future<bool> renameRemote(String id, String newName) async {
    if (api == null) return false;
    await api!.updateLibraryPreset(id, {'name': newName});
    return true;
  }

  @override
  Future<bool> deleteRemote(String id) async {
    if (api == null) return false;
    await api!.deleteLibraryPreset(id);
    return true;
  }
}