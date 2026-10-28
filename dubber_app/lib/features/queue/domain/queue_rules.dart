/// Queue rules shared by the New and Queue screens.
library;

import 'package:flutter/foundation.dart';

/// Maximum videos a user may have waiting in the queue.
const int maxQueuePerUser = 20;

/// Maximum files added from the Queue picker in one go.
const int maxFilesPerAdd = 10;

/// Maximum size of one file: 2 GB.
const int maxFileBytes = 2 * 1024 * 1024 * 1024;

/// Maximum duration of one video: 60 minutes.
const int maxDurationSeconds = 60 * 60;

/// Maximum uploads running at the same time.
const int maxConcurrentUploads = 2;

/// Accepted file extensions.
const Set<String> acceptedExtensions = {
  'mp4',
  'mov',
  'm4v',
  'mp3',
  'wav',
  'm4a',
  'aac',
};

/// A file chosen by the user, before validation.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    required this.path,
    this.bytes,
    this.durationSeconds,
  });

  final String name;
  final int size;
  final String path;

  /// In-memory bytes (available on Web and platforms where direct file path access is restricted).
  final Uint8List? bytes;

  /// Null when the platform could not read it.
  final int? durationSeconds;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';

  String get sizeLabel {
    if (size >= 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (size >= 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / 1024).toStringAsFixed(0)} KB';
  }

  PickedFile copyWith({int? durationSeconds, Uint8List? bytes}) => PickedFile(
        name: name,
        size: size,
        path: path,
        bytes: bytes ?? this.bytes,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}

/// Why a file was rejected. Each maps to a clear message.
enum FileProblem {
  unsupportedType,
  tooLarge,
  tooLong,
  unreadable,
}

extension FileProblemMessage on FileProblem {
  String get message => switch (this) {
        FileProblem.unsupportedType =>
          'This file type is not supported. Use MP4, MOV, MP3, WAV or M4A.',
        FileProblem.tooLarge => 'This file is larger than 2 GB.',
        FileProblem.tooLong => 'This video is longer than 60 minutes.',
        FileProblem.unreadable => 'We could not read this file.',
      };
}

/// The outcome of validating one file.
class FileValidation {
  const FileValidation({required this.file, this.problem});

  final PickedFile file;
  final FileProblem? problem;

  bool get isValid => problem == null;

  String? get message => problem?.message;
}

/// What will happen when the user adds [files] to the queue.
///
/// Built before anything is uploaded or charged, so the screen can say exactly
/// which files are going in and why the others are not.
class AddPlan {
  const AddPlan({
    required this.accepted,
    required this.invalid,
    required this.overQueue,
    required this.overCredits,
    required this.perFileCredits,
  });

  /// Files that will be added, in the user's order.
  final List<PickedFile> accepted;

  /// Files rejected by their own rules (type, size, duration).
  final List<FileValidation> invalid;

  /// Valid files that do not fit in the queue.
  final List<PickedFile> overQueue;

  /// Valid files that the balance cannot pay for.
  final List<PickedFile> overCredits;

  final int perFileCredits;

  int get reservedCredits => perFileCredits * accepted.length;
  int get rejectedCount => invalid.length + overQueue.length + overCredits.length;
  bool get isEmpty => accepted.isEmpty;
}

/// Validation rules. Pure functions so they are testable without widgets.
abstract final class QueueRules {
  /// Works out which files can be added, in order.
  ///
  /// Credits are reserved in the order the user picked the files, so the first
  /// N that fit are accepted. Files rejected here never reach the server.
  static AddPlan planAdd({
    required List<PickedFile> files,
    required int currentQueueSize,
    required int remainingCredits,
    required int perFileCredits,
  }) {
    final valid = <PickedFile>[];
    final invalid = <FileValidation>[];
    for (final file in files) {
      final result = validate(file);
      result.isValid ? valid.add(file) : invalid.add(result);
    }

    final room = queueRoom(currentQueueSize);
    final accepted = <PickedFile>[];
    final overQueue = <PickedFile>[];
    final overCredits = <PickedFile>[];

    var spent = 0;
    for (var i = 0; i < valid.length; i++) {
      final file = valid[i];
      if (i >= room) {
        overQueue.add(file);
        continue;
      }
      final next = spent + perFileCredits;
      if (perFileCredits > 0 && next > remainingCredits) {
        overCredits.add(file);
        continue;
      }
      accepted.add(file);
      spent = next;
    }

    return AddPlan(
      accepted: accepted,
      invalid: invalid,
      overQueue: overQueue,
      overCredits: overCredits,
      perFileCredits: perFileCredits,
    );
  }
  /// Validates one file on its own. Never throws.
  static FileValidation validate(PickedFile file) {
    if (file.path.isEmpty && (file.bytes == null || file.bytes!.isEmpty)) {
      return FileValidation(file: file, problem: FileProblem.unreadable);
    }
    if (!acceptedExtensions.contains(file.extension)) {
      return FileValidation(file: file, problem: FileProblem.unsupportedType);
    }
    if (file.size > maxFileBytes) {
      return FileValidation(file: file, problem: FileProblem.tooLarge);
    }
    final duration = file.durationSeconds;
    if (duration != null && duration > maxDurationSeconds) {
      return FileValidation(file: file, problem: FileProblem.tooLong);
    }
    return FileValidation(file: file);
  }

  /// Splits a selection into valid and invalid files.
  static ({List<PickedFile> valid, List<FileValidation> invalid}) partition(
    List<PickedFile> files,
  ) {
    final valid = <PickedFile>[];
    final invalid = <FileValidation>[];
    for (final file in files) {
      final result = validate(file);
      if (result.isValid) {
        valid.add(file);
      } else {
        invalid.add(result);
      }
    }
    return (valid: valid, invalid: invalid);
  }

  /// How many of [files] fit within [remainingCredits] at [perFileCredits].
  ///
  /// Credits are reserved in order, so the first N that fit are kept.
  static int howManyFit({
    required int remainingCredits,
    required int perFileCredits,
    required int fileCount,
  }) {
    if (perFileCredits <= 0) return fileCount;
    return (remainingCredits ~/ perFileCredits).clamp(0, fileCount);
  }

  /// Total credits for [count] videos.
  static int totalCredits(int perFileCredits, int count) =>
      perFileCredits * count;

  /// True when adding [count] more videos would exceed the queue limit.
  static bool queueWouldOverflow({
    required int currentQueueSize,
    required int count,
  }) =>
      currentQueueSize + count > maxQueuePerUser;

  /// How many more videos fit in the queue.
  static int queueRoom(int currentQueueSize) =>
      (maxQueuePerUser - currentQueueSize).clamp(0, maxQueuePerUser);

  /// The New screen button label.
  static String newButtonLabel({int? credits}) =>
      credits == null ? 'Start dubbing' : 'Start dubbing · $credits credits';
}

/// A stable idempotency key for one file, so a retry never double-charges.
///
/// Two FNV-1a passes over 32-bit words: the result is identical on the phone
/// and in a browser, where 64-bit integer literals are not exact.
String idempotencyKeyFor(PickedFile file, String sourceCode, String targetCode) {
  final identifier = file.path.isNotEmpty ? file.path : file.name;
  final raw = '$identifier|${file.size}|$sourceCode|$targetCode';

  var a = 0x811c9dc5;
  var b = 0x01000193;
  for (final unit in raw.codeUnits) {
    a = _fnvStep(a, unit);
    b = _fnvStep(b, unit ^ 0x5bd1e995);
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

int _fnvStep(int hash, int unit) {
  hash = (hash ^ (unit & 0xffff)) & 0xffffffff;
  return (hash * 0x01000193) & 0xffffffff;
}

/// MIME type from a file extension.
String mimeForFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    _ => 'application/octet-stream',
  };
}
