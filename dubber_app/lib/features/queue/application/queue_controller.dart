import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_error.dart';
import '../../projects/domain/models.dart';

/// Which queue screen state to show.
enum QueuePhase { loading, empty, error, offline, data }

class QueueState {
  const QueueState({
    this.nowDubbing,
    this.upNext = const [],
    this.failed = const [],
    this.phase = QueuePhase.loading,
    this.error,
    this.busyIds = const {},
    this.slotsLeft = 0,
    this.justFinished = const [],
    this.justFailed = const [],
  });

  /// The single job the server is working on.
  final Project? nowDubbing;

  /// Waiting jobs, in order; each carries its 1-based [Project.position].
  final List<Project> upNext;

  /// Jobs that stopped with an error. They keep their place until retried.
  final List<Project> failed;

  final QueuePhase phase;
  final ApiError? error;

  /// Project ids with an action in flight (remove / retry / move).
  final Set<String> busyIds;

  /// How many more videos the server will accept.
  final int slotsLeft;

  /// Titles that finished on the last poll, for the grouped message.
  final List<String> justFinished;

  /// Titles that failed on the last poll, for the grouped message.
  final List<String> justFailed;

  bool get isEmpty =>
      nowDubbing == null && upNext.isEmpty && failed.isEmpty;

  /// The number shown on the Queue tab badge.
  int get badgeCount => (nowDubbing == null ? 0 : 1) + upNext.length;

  QueueState copyWith({
    Project? nowDubbing,
    bool clearNowDubbing = false,
    List<Project>? upNext,
    List<Project>? failed,
    QueuePhase? phase,
    ApiError? error,
    bool clearError = false,
    Set<String>? busyIds,
    int? slotsLeft,
    List<String>? justFinished,
    List<String>? justFailed,
  }) =>
      QueueState(
        nowDubbing: clearNowDubbing ? null : (nowDubbing ?? this.nowDubbing),
        upNext: upNext ?? this.upNext,
        failed: failed ?? this.failed,
        phase: phase ?? this.phase,
        error: clearError ? null : (error ?? this.error),
        busyIds: busyIds ?? this.busyIds,
        slotsLeft: slotsLeft ?? this.slotsLeft,
        justFinished: justFinished ?? this.justFinished,
        justFailed: justFailed ?? this.justFailed,
      );
}

/// Loads the queue and polls it.
///
/// Polling rules from the spec:
/// - every 3 s while the Queue tab is visible
/// - every 10 s otherwise
/// - stop when the list is empty
/// - pause while the app is in the background
class QueueController extends StateNotifier<QueueState> {
  QueueController(this._ref) : super(const QueueState());

  final Ref _ref;
  Timer? _timer;
  bool _visible = true;
  bool _foreground = true;

  /// Ids seen on the previous poll, so the first load never reports "finished".
  Set<String>? _seen;
  bool _disposed = false;

  static const _activeInterval = Duration(seconds: 3);
  static const _idleInterval = Duration(seconds: 10);

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  /// Called when the Queue tab becomes visible or is left.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _reschedule();
    if (visible) refresh(silent: true);
  }

  /// Called from the app lifecycle observer.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _reschedule();
    if (foreground) refresh(silent: true);
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent && state.isEmpty) {
      state = state.copyWith(phase: QueuePhase.loading, clearError: true);
    }
    try {
      final q = await _ref.read(apiProvider).queue();
      if (_disposed) return;

      final now = q.nowDubbing;
      final active = [
        if (now != null) now.id,
        for (final p in q.upNext) p.id,
      ];
      final previous = _seen;
      final finished = <String>[];
      final madeFailures = <String>[];

      if (previous != null) {
        // Anything that was active last poll and is gone from the queue is
        // either done (it lives in Projects now) or failed and dropped out.
        final current = {...active, for (final p in q.failed) p.id};
        for (final id in previous.difference(current)) {
          finished.add(id);
        }
        for (final p in q.failed) {
          if (!previous.contains(p.id)) madeFailures.add(p.title);
        }
      }
      _seen = {...active, for (final p in q.failed) p.id};

      final empty = now == null && q.upNext.isEmpty && q.failed.isEmpty;
      state = QueueState(
        nowDubbing: now,
        upNext: q.upNext,
        failed: q.failed,
        phase: empty ? QueuePhase.empty : QueuePhase.data,
        busyIds: state.busyIds,
        slotsLeft: q.slotsLeft,
        // Finished ids have no title after they leave; the caller only needs
        // the count, so map them to an empty title.
        justFinished: List.filled(finished.length, ''),
        justFailed: madeFailures,
      );
      _reschedule();
    } catch (e) {
      if (_disposed) return;
      final err = e is ApiError ? e : const ApiError.unknown();
      final offline = err.code == 'offline' ||
          err.code == 'connection_lost' ||
          err.code == 'timeout';
      state = state.copyWith(
        phase: offline ? QueuePhase.offline : QueuePhase.error,
        error: err,
      );
      _reschedule();
    }
  }

  /// Clears the one-shot finish/fail notices once shown.
  void clearNotices() => state = state.copyWith(justFinished: const [], justFailed: const []);

  void _reschedule() {
    _timer?.cancel();
    _timer = null;

    // Nothing to watch, or the app is not in front: no polling.
    if (!_foreground) return;
    if (state.phase == QueuePhase.empty) return;

    final interval = _visible ? _activeInterval : _idleInterval;
    _timer = Timer.periodic(interval, (_) => refresh(silent: true));
  }

  /// Removes a waiting job. Credits come back from the server.
  Future<void> remove(Project project) async {
    _setBusy(project.id, true);
    try {
      await _ref.read(apiProvider).removeFromQueue(project.id);
      state = state.copyWith(
        upNext: state.upNext.where((p) => p.id != project.id).toList(),
      );
      await refresh(silent: true);
    } finally {
      _setBusy(project.id, false);
    }
  }

  /// Moves a waiting job to the front of the line.
  Future<void> moveToTop(Project project) async {
    _setBusy(project.id, true);
    try {
      await _ref.read(apiProvider).moveToTop(project.id);
      await refresh(silent: true);
    } finally {
      _setBusy(project.id, false);
    }
  }

  /// Saves a new waiting order. [ordered] is the up-next list, front to back.
  Future<void> reorder(List<Project> ordered) async {
    final ids = [for (final p in ordered) p.id];
    // Optimistic: the list moves under the finger immediately.
    state = state.copyWith(
      upNext: [
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(position: i + 1),
      ],
    );
    try {
      await _ref.read(apiProvider).reorderQueue(ids);
      await refresh(silent: true);
    } catch (_) {
      // Put the server's order back.
      await refresh(silent: true);
      rethrow;
    }
  }

  /// Starts a failed job again.
  Future<void> retry(Project project) async {
    _setBusy(project.id, true);
    try {
      await _ref.read(apiProvider).retryQueueItem(project.id);
      await refresh(silent: true);
    } finally {
      _setBusy(project.id, false);
    }
  }

  void _setBusy(String id, bool busy) {
    final ids = {...state.busyIds};
    busy ? ids.add(id) : ids.remove(id);
    state = state.copyWith(busyIds: ids);
  }
}

final queueControllerProvider =
    StateNotifierProvider<QueueController, QueueState>((ref) {
  return QueueController(ref);
});