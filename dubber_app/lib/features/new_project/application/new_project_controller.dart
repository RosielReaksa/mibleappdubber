import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_error.dart';
import '../../auth/application/auth_controller.dart';
import '../../projects/domain/models.dart';
import '../../queue/domain/queue_rules.dart';

/// Where the New screen is in its lifecycle.
enum NewPhase {
  /// Still checking whether the user already has a job.
  checking,

  /// The user has a processing or queued job: New is blocked.
  blocked,

  /// Nothing is active: the user may start one video.
  ready,
}

class NewProjectState {
  const NewProjectState({
    this.phase = NewPhase.checking,
    this.languages = const [],
    this.voices = const [],
    this.loadingContent = false,
    this.contentError,
    this.sourceCode,
    this.targetCode,
    this.format = VideoFormat.landscape,
    this.voice = VoiceChoice.female,
    this.mix = const AudioMix(),
    this.file,
    this.fileError,
    this.estimate,
    this.estimating = false,
    this.creating = false,
    this.createError,
    this.uploadProgress,
    this.template,
    this.templateFields = const {},
    this.blockingProject,
    this.validationProblem,
  });

  final NewPhase phase;
  final List<Language> languages;
  final List<Voice> voices;
  final bool loadingContent;
  final ApiError? contentError;

  final String? sourceCode;
  final String? targetCode;
  final VideoFormat format;
  final VoiceChoice voice;
  final AudioMix mix;

  /// The single file for this dubbing.
  final PickedFile? file;
  final String? fileError;

  /// Credits for this video.
  final int? estimate;
  final bool estimating;
  final bool creating;
  final ApiError? createError;

  /// 0..1 while the file uploads, null before it starts.
  final double? uploadProgress;

  final Template? template;
  final Set<String> templateFields;

  /// The job that is stopping this user from starting another.
  final Project? blockingProject;

  /// Why the chosen file was rejected, if it was.
  final FileProblem? validationProblem;

  bool get isBlocked => phase == NewPhase.blocked;
  bool get isChecking => phase == NewPhase.checking;

  bool get canStart =>
      phase == NewPhase.ready &&
      file != null &&
      validationProblem == null &&
      sourceCode != null &&
      targetCode != null &&
      !creating &&
      !estimating;

  String get startLabel => QueueRules.newButtonLabel(credits: estimate);

  /// "A video is already dubbing." — the message New shows when blocked.
  static const blockedMessage =
      'A video is already dubbing. Add more videos from the Queue tab.';

  NewProjectState copyWith({
    NewPhase? phase,
    List<Language>? languages,
    List<Voice>? voices,
    bool? loadingContent,
    ApiError? contentError,
    bool clearContentError = false,
    String? sourceCode,
    String? targetCode,
    VideoFormat? format,
    VoiceChoice? voice,
    AudioMix? mix,
    PickedFile? file,
    bool clearFile = false,
    String? fileError,
    bool clearFileError = false,
    int? estimate,
    bool clearEstimate = false,
    bool? estimating,
    bool? creating,
    ApiError? createError,
    bool clearCreateError = false,
    double? uploadProgress,
    bool clearUploadProgress = false,
    Template? template,
    bool clearTemplate = false,
    Set<String>? templateFields,
    Project? blockingProject,
    bool clearBlocking = false,
    FileProblem? validationProblem,
    bool clearValidation = false,
  }) =>
      NewProjectState(
        phase: phase ?? this.phase,
        languages: languages ?? this.languages,
        voices: voices ?? this.voices,
        loadingContent: loadingContent ?? this.loadingContent,
        contentError:
            clearContentError ? null : (contentError ?? this.contentError),
        sourceCode: sourceCode ?? this.sourceCode,
        targetCode: targetCode ?? this.targetCode,
        format: format ?? this.format,
        voice: voice ?? this.voice,
        mix: mix ?? this.mix,
        file: clearFile ? null : (file ?? this.file),
        fileError: clearFileError ? null : (fileError ?? this.fileError),
        estimate: clearEstimate ? null : (estimate ?? this.estimate),
        estimating: estimating ?? this.estimating,
        creating: creating ?? this.creating,
        createError: clearCreateError ? null : (createError ?? this.createError),
        uploadProgress: clearUploadProgress
            ? null
            : (uploadProgress ?? this.uploadProgress),
        template: clearTemplate ? null : (template ?? this.template),
        templateFields: templateFields ?? this.templateFields,
        blockingProject:
            clearBlocking ? null : (blockingProject ?? this.blockingProject),
        validationProblem: clearValidation
            ? null
            : (validationProblem ?? this.validationProblem),
      );
}

/// How a start attempt ended.
sealed class StartOutcome {
  const StartOutcome();
}

/// The job was created and is now dubbing.
final class StartOk extends StartOutcome {
  const StartOk(this.project);
  final Project project;
}

/// Another job is processing or queued; nothing was created.
final class StartBlocked extends StartOutcome {
  const StartBlocked(this.project);
  final Project? project;
}

/// The start failed for another reason.
final class StartFailed extends StartOutcome {
  const StartFailed(this.error);
  final ApiError error;
}

class NewProjectController extends StateNotifier<NewProjectState> {
  NewProjectController(this._ref) : super(const NewProjectState());

  final Ref _ref;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Loads languages, voices, and whether the user may start a job.
  Future<void> load() async {
    state = state.copyWith(phase: NewPhase.checking);
    await Future.wait([loadContent(), checkCanStart()]);
  }

  /// Loads languages and voices. Safe to call again after an error.
  Future<void> loadContent() async {
    state = state.copyWith(loadingContent: true, clearContentError: true);
    try {
      final api = _ref.read(apiProvider);
      final results = await Future.wait([api.languages(), api.voices()]);
      final languages = results[0] as List<Language>;
      final voices = results[1] as List<Voice>;
      state = state.copyWith(
        languages: languages,
        voices: voices,
        loadingContent: false,
        sourceCode:
            state.sourceCode ?? (languages.isNotEmpty ? languages.first.code : null),
        targetCode:
            state.targetCode ?? (languages.length > 1 ? languages[1].code : null),
      );
      _scheduleEstimate();
    } catch (e) {
      state = state.copyWith(
        loadingContent: false,
        contentError: e is ApiError ? e : const ApiError.unknown(),
      );
    }
  }

  /// Asks the server whether anything is processing or queued.
  ///
  /// This decides whether New shows the form or the "already dubbing" message.
  Future<void> checkCanStart() async {
    try {
      final active = await _ref.read(apiProvider).activeProject();
      if (!mounted) return;
      state = active == null
          ? state.copyWith(phase: NewPhase.ready, clearBlocking: true)
          : state.copyWith(
              phase: NewPhase.blocked,
              blockingProject: active,
            );
      if (active == null) _scheduleEstimate();
    } catch (_) {
      // If we cannot check, do not block the user; submit re-checks on the
      // server and returns `already_dubbing` if needed.
      if (mounted) state = state.copyWith(phase: NewPhase.ready);
    }
  }

  void applyTemplate(Template template) {
    final fields = <String>{};
    if (template.format != null) fields.add('format');
    if (template.mix != null) fields.add('mix');
    if (template.subtitlesOn || template.subtitleStyle != null) {
      fields.add('subtitles');
    }
    if (template.fitMode != null) fields.add('fit');
    if (template.logoPosition != null) fields.add('logo');

    state = state.copyWith(
      template: template,
      templateFields: fields,
      format: template.format ?? state.format,
      mix: template.mix ?? state.mix,
    );
  }

  /// Clears the chosen template, leaving the user's current settings alone.
  ///
  /// Tapping the "None" chip returns the form to its manual state: the banner
  /// and every "From template" tag disappear, and nothing else changes.
  void clearTemplate() => state = state.copyWith(
        clearTemplate: true,
        templateFields: const {},
      );

  void setSource(String code) {
    state = state.copyWith(sourceCode: code, clearEstimate: true);
    _scheduleEstimate();
  }

  void setTarget(String code) {
    state = state.copyWith(targetCode: code, clearEstimate: true);
    _scheduleEstimate();
  }

  void setFormat(VideoFormat format) {
    state = state.copyWith(
      format: format,
      templateFields: {...state.templateFields}..remove('format'),
      clearEstimate: true,
    );
    _scheduleEstimate();
  }

  void setVoice(VoiceChoice voice) {
    state = state.copyWith(voice: voice, clearEstimate: true);
    _scheduleEstimate();
  }

  void setMix(AudioMix mix) {
    state = state.copyWith(
      mix: mix,
      templateFields: {...state.templateFields}..remove('mix'),
    );
  }

  /// Sets the one file, or rejects it with a clear reason.
  void setFile(PickedFile picked) {
    final result = QueueRules.validate(picked);
    if (!result.isValid) {
      state = state.copyWith(
        clearFile: true,
        validationProblem: result.problem,
        fileError: result.message,
        clearEstimate: true,
      );
      return;
    }
    state = state.copyWith(
      file: picked,
      clearValidation: true,
      clearFileError: true,
      clearEstimate: true,
      clearCreateError: true,
    );
    _scheduleEstimate();
  }

  void clearFile() => state = state.copyWith(
        clearFile: true,
        clearValidation: true,
        clearFileError: true,
        clearEstimate: true,
      );

  void setFileError(String message) =>
      state = state.copyWith(fileError: message);

  /// Debounced re-estimate, 400 ms.
  void _scheduleEstimate() {
    _debounce?.cancel();
    final s = state;
    if (s.sourceCode == null || s.targetCode == null || s.file == null) {
      state = state.copyWith(clearEstimate: true, estimating: false);
      return;
    }
    state = state.copyWith(estimating: true);
    _debounce = Timer(const Duration(milliseconds: 400), _reestimate);
  }

  Future<void> _reestimate() async {
    final s = state;
    if (s.sourceCode == null || s.targetCode == null || s.file == null) return;
    try {
      final credits = await _ref.read(apiProvider).estimate(
            sourceLanguage: s.sourceCode!,
            targetLanguage: s.targetCode!,
            format: s.format,
            voice: s.voice,
          );
      if (mounted) state = state.copyWith(estimate: credits, estimating: false);
    } catch (_) {
      if (mounted) state = state.copyWith(estimating: false);
    }
  }

  void setCreating(bool value) =>
      state = state.copyWith(creating: value, clearCreateError: true);

  void setCreateError(ApiError error) =>
      state = state.copyWith(creating: false, createError: error);

  /// Starts the one video on this screen.
  ///
  /// The server decides whether the user may start: if anything is already
  /// processing or queued it answers `already_dubbing`, and this returns
  /// [StartBlocked] instead of creating a second job.
  Future<StartOutcome> start() async {
    final s = state;
    final file = s.file;
    if (file == null || s.sourceCode == null || s.targetCode == null) {
      return const StartFailed(
        ApiError(code: 'invalid', message: 'Choose a file and both languages.'),
      );
    }

    state = state.copyWith(creating: true, clearCreateError: true,
        uploadProgress: 0);

    try {
      final api = _ref.read(apiProvider);
      final uploadId = await api.uploadFile(
        path: file.path,
        fileName: file.name,
        mime: mimeForFile(file.name),
        bytesData: file.bytes,
        onProgress: (p) {
          if (mounted) state = state.copyWith(uploadProgress: p);
        },
      );

      final project = await api.createProject(
        uploadId: uploadId,
        sourceLanguage: s.sourceCode!,
        targetLanguage: s.targetCode!,
        format: s.format,
        voice: s.voice,
        mix: s.mix,
        templateId: s.template?.id,
        idempotencyKey: idempotencyKeyFor(file, s.sourceCode!, s.targetCode!),
      );

      if (!mounted) return StartOk(project);
      state = const NewProjectState(phase: NewPhase.ready);
      return StartOk(project);
    } on ApiError catch (e) {
      if (!mounted) return StartFailed(e);

      if (e.code == 'already_dubbing' || e.code == 'queue_full') {
        // Someone else started a job first. Show the blocked state.
        state = state.copyWith(
          creating: false,
          clearUploadProgress: true,
          phase: NewPhase.blocked,
          clearCreateError: true,
        );
        // Learn which job is blocking, if the server will tell us.
        unawaited(checkCanStart());
        return StartBlocked(null);
      }

      if (e.code == 'not_enough_credits') {
        state = state.copyWith(
          creating: false,
          clearUploadProgress: true,
          createError: e,
        );
        return StartFailed(e);
      }

      state = state.copyWith(
        creating: false,
        clearUploadProgress: true,
        createError: e,
      );
      return StartFailed(e);
    } catch (_) {
      const error = ApiError.unknown();
      if (mounted) {
        state = state.copyWith(
          creating: false,
          clearUploadProgress: true,
          createError: error,
        );
      }
      return const StartFailed(error);
    }
  }

  /// Called after a job starts; the screen moves to the Queue.
  void reset() => state = const NewProjectState();
}

final newProjectControllerProvider =
    StateNotifierProvider<NewProjectController, NewProjectState>((ref) {
  return NewProjectController(ref);
});
