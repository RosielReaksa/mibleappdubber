import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for Library sections, behind a narrow interface.
///
/// The Library repositories never talk to a database directly: they call this.
/// That keeps the storage engine swappable (drift, shared preferences, or an
/// in-memory fake in tests) without touching repository logic.
abstract class LibraryLocalStore {
  /// Every item in [section], or an empty list when nothing is stored.
  Future<List<Map<String, dynamic>>> read(String section);

  /// Replaces the whole [section] with [items].
  Future<void> write(String section, List<Map<String, dynamic>> items);
}

/// JSON-in-shared-preferences store.
///
/// TODO(server): replace with the drift database described in the build spec
/// (section 9) once the Library endpoints exist. This store is good enough to
/// satisfy the offline requirement and keeps every repository call identical.
class PrefsLibraryLocalStore implements LibraryLocalStore {
  PrefsLibraryLocalStore([Future<SharedPreferences>? prefs])
      : _prefs = prefs;

  final Future<SharedPreferences>? _prefs;

  static const _prefix = 'library_v1_';

  Future<SharedPreferences> get _instance =>
      _prefs ?? SharedPreferences.getInstance();

  @override
  Future<List<Map<String, dynamic>>> read(String section) async {
    try {
      final prefs = await _instance;
      final raw = prefs.getString('$_prefix$section');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      // A corrupt or unreadable cache is treated as empty; the server refresh
      // replaces it. Never let storage break a screen.
      return const [];
    }
  }

  @override
  Future<void> write(String section, List<Map<String, dynamic>> items) async {
    try {
      final prefs = await _instance;
      await prefs.setString('$_prefix$section', jsonEncode(items));
    } catch (_) {
      // Failing to cache must not fail the user's action.
    }
  }
}

/// In-memory store for tests and for the very first frame before storage opens.
class MemoryLibraryLocalStore implements LibraryLocalStore {
  MemoryLibraryLocalStore([Map<String, List<Map<String, dynamic>>>? seed])
      : _data = seed ?? {};

  final Map<String, List<Map<String, dynamic>>> _data;

  @override
  Future<List<Map<String, dynamic>>> read(String section) async =>
      List.of(_data[section] ?? const []);

  @override
  Future<void> write(String section, List<Map<String, dynamic>> items) async {
    _data[section] = List.of(items);
  }
}