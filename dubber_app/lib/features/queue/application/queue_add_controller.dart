import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_error.dart';
import '../../auth/application/auth_controller.dart';
import '../../projects/data/dubber_api.dart';
import '../../projects/domain/models.dart';
import '../domain/dubbing_options.dart';
import '../domain/queue_rules.dart';

/// Where one file is in the add flow.
enum AddFileState {
  /// The add has not started for this file.
  waiting,

  /// Waiting for a free upload slot.
  waitingToUpload,

  uploading,

  /// Uploaded, waiting for the server to accept it into the queue.
  verifying,

  added,

  /// Rejected by the client before upload, or by the server afterwards.
  rejected,
}

/// One file in the add flow.
class AddFile {
  const AddFile({
    required this.file,
    required this.options,
    this.state = AddFileState.waiting,
    this.progress = 0,
    this.reason,
  });

  final PickedFile file;
  final DubbingOptions options;
  final AddFileState state;

  /// 0..1 while uploading.
  final double progress;

  /// Why it was rejected, in the user's words.
  final String? reason;

  bool get isRejected => state == AddFileState.rejected;
  bool get isAdded => state == AddFileState.added;

  AddFile copyWith({
    DubbingOptions? options,
    AddFileState? state,
    double? progress,
    String? reason,
  }) =>
      AddFile(
        file: file,
        options: options ?? this.options,
        state: state ?? this.state,
        progress: progress ?? this.progress,
        reason: reason ?? this.reason,
      );
}

class QueueAddState {
  const QueueAddState({
    this.files = const [],
    this.started = false,
    this.startingUploads = false,
    this.brushing = false,
    this.notice,
    this.error,
  });

  final List<AddFile> files;

  /// True once the server call has been sent.
  final bool started;

  final bool startingUploads;
  final bool brushing;

  /// What to tell the user when the add ends, e.g. which files were not added.
  final String? notice;
  final ApiError? error;

  /// Files that will be sent: valid ones the balance and queue allow.
  List<AddFile> get toSend =>
      files.where((f) => !f.isRejected && !f.isAdded).toList();

  int get readyCount =>
      files.where((f) => f.state == AddFileState.waiting && !f.isRejected).length;

  int get addedCount => files.where((f) => f.isAdded).length;
  int get rejectedCount => files.where((f) => f.isRejected).length;

  bool get busy => startingUploads || started;
  bool get canStart => !busy && toSend.isNotEmpty;

  QueueAddState copyWith({
    List<AddFile>? files,
    bool? started,
    bool? startingUploads,
    bool? brushing,
    String? notice,
    bool clearNotice = false,
    ApiError? error,
    bool clearError = false,
  }) =>
      QueueAddState(
        files: files ?? this.files,
        started: started ?? this.started,
        startingUploads: startingUploads ?? this.startingUploads,
        brushing: brushing ?? this.brushing,
        notice: clearNotice ? null : (notice ?? this.notice),
        error: clearError ? null : (error ?? this.error),
      );
}

/// Drives "Add videos": validates, uploads with a concurrency cap, then asks
/// the server to add the uploaded videos to the queue.
///
/// Credits and the queue limit are decided by the server per item, in order;
/// this class only pre-checks them so the user is not surprised.
class QueueAddController extends StateNotifier<QueueAddState> {
  QueueAddController(this._ref) : super(const QueueAddState());

  final Ref _ref;

  /// Loads the picker with [files] all sharing [options].
  ///
  /// Files that fail validation are kept in the list with their reason, so the
  /// user sees exactly which ones are going in and which are not.
  Future<void> begin({
    required List<PickedFile> files,
    required DubbingOptions options,
    required int perFileCredits,
  }) async {
    // Ask the server for fresh numbers: balance and room in the queue.
    var balance = _ref.read(authControllerProvider).session?.credits ?? 0;
    var currentQueueSize = 0;
    try {
      final api = _ref.read(apiProvider);
      final credits = await api.credits();
      balance = credits.balance;
      final q = await api.queue();
      currentQueueSize = 1 + q.upNext.length;
    } catch (_) {
      // The server re-checks on add, so a failed pre-check must not block.
    }
    if (!mounted) return;

    // The queue limit and the balance are the server's business; this plan
    // only stops the user from uploading files that would be refused.
    final plan = QueueRules.planAdd(
      files: files,
      currentQueueSize: currentQueueSize,
      remainingCredits: balance,
      perFileCredits: perFileCredits,
    );

    final byFile = <PickedFile, String>{
      for (final v in plan.invalid) v.file: v.message ?? 'Not supported.',
      for (final f in plan.overQueue) f: 'Your queue is full.',
      for (final f in plan.overCredits)
        f: 'Not enough credits for this video.',
    };

    state = QueueAddState(
      files: [
        for (final f in files)
          AddFile(
            file: f,
            options: options,
            state: byFile.containsKey(f)
                ? AddFileState.rejected
                : AddFileState.waiting,
            reason: byFile[f],
          ),
      ],
    );
  }

  /// Changes the settings for every file that has not been sent yet.
  void applyToAll(DubbingOptions options) {
    state = state.copyWith(
      files: [
        for (final f in state.files)
          f.isRejected || f.isAdded ? f : f.copyWith(options: options),
      ],
    );
  }

  /// Changes the settings for one file only.
  void applyTo(int index, DubbingOptions options) {
    final files = [...state.files];
    if (index < 0 || index >= files.length) return;
    if (files[index].isAdded) return;
    files[index] = files[index].copyWith(options: options);
    state = state.copyWith(files: files);
  }

  /// Removes a file from the add before it is sent.
  void removeFile(int index) {
    if (index < 0 || index >= state.files.length) return;
    final files = [...state.files]..removeAt(index);
    state = state.copyWith(files: files);
  }

  /// Uploads then adds. Returns the server's answer, or null on failure.
  Future<QueueAddResponse?> run() async {
    final toSend = state.toSend;
    if (toSend.isEmpty) return null;

    state = state.copyWith(
      started: true,
      startingUploads: true,
      clearNotice: true,
      clearError: true,
    );

    final api = _ref.read(apiProvider);
    final uploadIds = <String, String>{}; // file path -> upload id
    final uploadErrors = <String, ApiError>{};

    // Upload with a hard cap on simultaneous transfers.
    final queue = [...toSend];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final item = queue.removeAt(0);
        var index = state.files.indexWhere((f) => f.file.path == item.file.path);
        if (index < 0) continue;
        _setFile(index, state.files[index].copyWith(state: AddFileState.uploading));
        try {
          final id = await api.uploadFile(
            path: item.file.path,
            fileName: item.file.name,
            mime: mimeForFile(item.file.name),
            bytesData: item.file.bytes,
            onProgress: (p) {
              if (!mounted) return;
              final i =
                  state.files.indexWhere((f) => f.file.path == item.file.path);
              if (i >= 0) {
                _setFile(i, state.files[i].copyWith(progress: p));
              }
            },
          );
          uploadIds[item.file.path] = id;
          index = state.files.indexWhere((f) => f.file.path == item.file.path);
          if (index >= 0) {
            _setFile(
              index,
              state.files[index].copyWith(
                state: AddFileState.verifying,
                progress: 1,
              ),
            );
          }
        } catch (e) {
          final err = e is ApiError ? e : const ApiError.unknown();
          uploadErrors[item.file.path] = err;
          index = state.files.indexWhere((f) => f.file.path == item.file.path);
          if (index >= 0 && mounted) {
            _setFile(
              index,
              state.files[index].copyWith(
                state: AddFileState.rejected,
                reason: err.message,
              ),
            );
          }
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < maxConcurrentUploads; i++) worker(),
    ]);

    if (!mounted) return null;
    state = state.copyWith(startingUploads: false);

    final items = [
      for (final f in state.files)
        if (uploadIds.containsKey(f.file.path))
          {...f.options.toItemJson(f.file), 'upload_id': uploadIds[f.file.path]},
    ];

    if (items.isEmpty) {
      state = state.copyWith(
        started: false,
        error: uploadErrors.values.firstOrNull ?? const ApiError.unknown(),
      );
      return null;
    }

    try {
      final response = await api.addToQueue(items: items);
      if (!mounted) return response;

      // The server's answer is the truth: mark what it took and what it did not.
      final addedNames = {for (final p in response.added) p.title};
      final rejectedByServer = {
        for (final r in response.rejected) r.fileName: r.message,
      };

      state = state.copyWith(
        started: false,
        files: [
          for (final f in state.files)
            _resolve(f, addedNames, rejectedByServer, response.stoppedReason),
        ],
        notice: _noticeFor(response),
      );

      // The server reserved credits; take its balance so every screen agrees.
      if (response.balance != null) {
        await _ref
            .read(authControllerProvider.notifier)
            .setCredits(response.balance!);
      }
      return response;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        started: false,
        error: e is ApiError ? e : const ApiError.unknown(),
      );
      return null;
    }
  }

  AddFile _resolve(
    AddFile f,
    Set<String> addedNames,
    Map<String, String> rejectedByServer,
    String? stoppedReason,
  ) {
    if (f.isRejected || f.isAdded) return f;
    if (addedNames.contains(f.file.name)) {
      return f.copyWith(state: AddFileState.added);
    }
    final serverReason = rejectedByServer[f.file.name];
    if (serverReason != null) {
      return f.copyWith(state: AddFileState.rejected, reason: serverReason);
    }
    return f.copyWith(
      state: AddFileState.rejected,
      reason: switch (stoppedReason) {
        'not_enough_credits' => 'Not enough credits for this video.',
        'max_queue_per_user' => 'Your queue is full.',
        _ => 'This video was not added.',
      },
    );
  }

  String _noticeFor(QueueAddResponse r) {
    final added = r.added.length;
    final notAdded = state.files.where((f) => f.isRejected).length;
    final queueFull = r.stoppedReason == 'max_queue_per_user';

    if (added == 0) {
      return queueFull ? 'Your queue is full.' : 'No videos were added.';
    }
    if (notAdded == 0) {
      return added == 1 ? '1 video added' : '$added videos added';
    }
    return '$added added · $notAdded not added';
  }

  void _setFile(int index, AddFile file) {
    if (index < 0 || index >= state.files.length) return;
    final files = [...state.files];
    files[index] = file;
    state = state.copyWith(files: files);
  }
}

final queueAddControllerProvider =
    StateNotifierProvider<QueueAddController, QueueAddState>((ref) {
  return QueueAddController(ref);
});