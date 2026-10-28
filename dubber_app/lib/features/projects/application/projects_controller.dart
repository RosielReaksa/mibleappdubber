import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_error.dart';
import '../domain/models.dart';

class ProjectsState {
  const ProjectsState({
    this.projects = const [],
    this.loading = false,
    this.error,
    this.offline = false,
    this.fromCache = false,
  });

  final List<Project> projects;
  final bool loading;
  final ApiError? error;

  /// True when the last refresh failed because of the network.
  final bool offline;
  final bool fromCache;

  bool get isEmpty => projects.isEmpty;

  ProjectsState copyWith({
    List<Project>? projects,
    bool? loading,
    ApiError? error,
    bool clearError = false,
    bool? offline,
    bool? fromCache,
  }) =>
      ProjectsState(
        projects: projects ?? this.projects,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        offline: offline ?? this.offline,
        fromCache: fromCache ?? this.fromCache,
      );
}

class ProjectsController extends StateNotifier<ProjectsState> {
  ProjectsController(this._ref) : super(const ProjectsState()) {
    _loadCache();
  }

  final Ref _ref;
  static const _cacheKey = 'cached_projects';

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Project.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      state = state.copyWith(projects: list, fromCache: true);
    } catch (_) {
      // A corrupt cache is not worth surfacing; refresh will replace it.
    }
  }

  Future<void> _saveCache(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode(projects.map((p) => p.toCacheJson()).toList()),
    );
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true, clearError: true);
    try {
      final projects = await _ref.read(apiProvider).projects();
      state = ProjectsState(projects: projects, fromCache: false);
      await _saveCache(projects);
    } catch (e) {
      final err = e is ApiError ? e : const ApiError.unknown();
      final offline = err.code == 'offline' ||
          err.code == 'connection_lost' ||
          err.code == 'timeout';
      state = state.copyWith(
        loading: false,
        error: err,
        offline: offline,
        // Keep whatever we have: cached rows stay visible offline.
      );
    }
  }

  Future<void> delete(String id) async {
    final previous = state.projects;
    state = state.copyWith(
      projects: previous.where((p) => p.id != id).toList(),
    );
    try {
      await _ref.read(apiProvider).deleteProject(id);
      await _saveCache(state.projects);
    } catch (e) {
      // Restore the row so the list matches the server.
      state = state.copyWith(
        projects: previous,
        error: e is ApiError ? e : const ApiError.unknown(),
      );
      rethrow;
    }
  }

  /// Update one project in place (after polling).
  void upsert(Project project) {
    final list = [...state.projects];
    final i = list.indexWhere((p) => p.id == project.id);
    if (i >= 0) {
      list[i] = project;
    } else {
      list.insert(0, project);
    }
    state = state.copyWith(projects: list);
    _saveCache(list);
  }
}

final projectsControllerProvider =
    StateNotifierProvider<ProjectsController, ProjectsState>((ref) {
  return ProjectsController(ref);
});
