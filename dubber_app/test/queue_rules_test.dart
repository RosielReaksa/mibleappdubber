import 'package:dubber_app/features/queue/domain/queue_rules.dart';
import 'package:flutter_test/flutter_test.dart';

PickedFile file(String name, {int size = 10 * 1024 * 1024, int? duration}) =>
    PickedFile(
      name: name,
      size: size,
      path: '/tmp/$name',
      durationSeconds: duration,
    );

void main() {
  group('File validation', () {
    test('accepts a normal video', () {
      expect(QueueRules.validate(file('talk.mp4')).isValid, isTrue);
    });

    test('accepts the audio types the picker offers', () {
      for (final name in ['a.mp3', 'b.wav', 'c.m4a']) {
        expect(QueueRules.validate(file(name)).isValid, isTrue, reason: name);
      }
    });

    test('rejects a type the server cannot dub', () {
      final result = QueueRules.validate(file('notes.txt'));
      expect(result.isValid, isFalse);
      expect(result.problem, FileProblem.unsupportedType);
      expect(result.message, contains('not supported'));
    });

    test('rejects a file over 2 GB', () {
      final result = QueueRules.validate(
        file('huge.mp4', size: maxFileBytes + 1),
      );
      expect(result.problem, FileProblem.tooLarge);
    });

    test('accepts exactly 2 GB', () {
      expect(QueueRules.validate(file('big.mp4', size: maxFileBytes)).isValid,
          isTrue);
    });

    test('rejects a video over 60 minutes', () {
      final result = QueueRules.validate(
        file('long.mp4', duration: maxDurationSeconds + 1),
      );
      expect(result.problem, FileProblem.tooLong);
    });

    test('accepts exactly 60 minutes', () {
      expect(
        QueueRules.validate(file('ok.mp4', duration: maxDurationSeconds)).isValid,
        isTrue,
      );
    });

    test('unknown duration is not a failure', () {
      expect(QueueRules.validate(file('unknown.mp4')).isValid, isTrue);
    });

    test('rejects a file with no path', () {
      const result = FileValidation(
        file: PickedFile(name: 'ghost.mp4', size: 1, path: ''),
        problem: FileProblem.unreadable,
      );
      expect(result.isValid, isFalse);
      expect(QueueRules.validate(const PickedFile(
        name: 'ghost.mp4', size: 1, path: '',
      )).problem, FileProblem.unreadable);
    });
  });

  group('planAdd', () {
    test('adds every valid file when credits and room allow', () {
      final plan = QueueRules.planAdd(
        files: [file('a.mp4'), file('b.mp4'), file('c.mp4')],
        currentQueueSize: 0,
        remainingCredits: 1000,
        perFileCredits: 12,
      );
      expect(plan.accepted.length, 3);
      expect(plan.rejectedCount, 0);
      expect(plan.reservedCredits, 36);
    });

    test('5 videos: 1 dubs and 4 wait, so 5 fit in an empty queue', () {
      // planAdd runs before the add, when nothing is active.
      final plan = QueueRules.planAdd(
        files: List.generate(5, (i) => file('v$i.mp4')),
        currentQueueSize: 0,
        remainingCredits: 1000,
        perFileCredits: 12,
      );
      expect(plan.accepted.length, 5);
      expect(plan.reservedCredits, 60);
    });

    test('one invalid file does not stop the others', () {
      final plan = QueueRules.planAdd(
        files: [file('a.mp4'), file('bad.txt'), file('c.mp4'), file('d.mp4')],
        currentQueueSize: 0,
        remainingCredits: 1000,
        perFileCredits: 12,
      );
      expect(plan.accepted.map((f) => f.name), ['a.mp4', 'c.mp4', 'd.mp4']);
      expect(plan.invalid.length, 1);
      expect(plan.invalid.single.problem, FileProblem.unsupportedType);
    });

    test('credits for only 3 of 5: the first 3 go in, in order', () {
      final plan = QueueRules.planAdd(
        files: List.generate(5, (i) => file('v$i.mp4')),
        currentQueueSize: 0,
        remainingCredits: 36, // exactly 3 × 12
        perFileCredits: 12,
      );
      expect(plan.accepted.map((f) => f.name), ['v0.mp4', 'v1.mp4', 'v2.mp4']);
      expect(plan.overCredits.map((f) => f.name), ['v3.mp4', 'v4.mp4']);
      // Reserved credits equal exactly the accepted videos.
      expect(plan.reservedCredits, 36);
    });

    test('a short balance reserves only what it can pay for', () {
      final plan = QueueRules.planAdd(
        files: [file('a.mp4'), file('b.mp4')],
        currentQueueSize: 0,
        remainingCredits: 20, // one video and 8 left over
        perFileCredits: 12,
      );
      expect(plan.accepted.length, 1);
      expect(plan.reservedCredits, 12);
      expect(plan.overCredits.length, 1);
    });

    test('respects the queue limit', () {
      final plan = QueueRules.planAdd(
        files: List.generate(5, (i) => file('v$i.mp4')),
        currentQueueSize: maxQueuePerUser - 2,
        remainingCredits: 1000,
        perFileCredits: 12,
      );
      expect(plan.accepted.length, 2);
      expect(plan.overQueue.length, 3);
    });

    test('a full queue accepts nothing and says so', () {
      final plan = QueueRules.planAdd(
        files: [file('a.mp4')],
        currentQueueSize: maxQueuePerUser,
        remainingCredits: 1000,
        perFileCredits: 12,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.overQueue.length, 1);
    });

    test('invalid files are charged neither credits nor slots', () {
      final plan = QueueRules.planAdd(
        files: [file('bad.txt'), file('ok.mp4')],
        currentQueueSize: maxQueuePerUser - 1,
        remainingCredits: 12,
        perFileCredits: 12,
      );
      expect(plan.accepted.single.name, 'ok.mp4');
      expect(plan.reservedCredits, 12);
      expect(plan.invalid.length, 1);
    });
  });

  group('Limits', () {
    test('the queue holds 20 videos and no more', () {
      expect(maxQueuePerUser, 20);
      expect(QueueRules.queueRoom(0), 20);
      expect(QueueRules.queueRoom(19), 1);
      expect(QueueRules.queueRoom(20), 0);
      expect(QueueRules.queueWouldOverflow(currentQueueSize: 19, count: 2), isTrue);
      expect(QueueRules.queueWouldOverflow(currentQueueSize: 18, count: 2), isFalse);
    });

    test('at most 10 files are added from one picker', () {
      expect(maxFilesPerAdd, 10);
    });

    test('at most 2 uploads run at the same time', () {
      expect(maxConcurrentUploads, 2);
    });
  });

  group('Credits', () {
    test('total for several videos', () {
      expect(QueueRules.totalCredits(12, 1), 12);
      expect(QueueRules.totalCredits(12, 5), 60);
    });

    test('how many fit in a balance', () {
      expect(
        QueueRules.howManyFit(
            remainingCredits: 36, perFileCredits: 12, fileCount: 5),
        3,
      );
      expect(
        QueueRules.howManyFit(
            remainingCredits: 0, perFileCredits: 12, fileCount: 5),
        0,
      );
      expect(
        QueueRules.howManyFit(
            remainingCredits: 1000, perFileCredits: 12, fileCount: 5),
        5,
      );
    });
  });

  group('Button label', () {
    test('one video reads like a single dubbing', () {
      expect(QueueRules.newButtonLabel(credits: 12),
          'Start dubbing · 12 credits');
    });

    test('no estimate yet still has a label', () {
      expect(QueueRules.newButtonLabel(), 'Start dubbing');
    });
  });

  group('Idempotency', () {
    test('the same file and languages give the same key', () {
      final a = idempotencyKeyFor(file('a.mp4'), 'en', 'km');
      final b = idempotencyKeyFor(file('a.mp4'), 'en', 'km');
      expect(a, b);
    });

    test('a different target language gives a different key', () {
      final a = idempotencyKeyFor(file('a.mp4'), 'en', 'km');
      final b = idempotencyKeyFor(file('a.mp4'), 'en', 'es');
      expect(a, isNot(b));
    });

    test('a different file gives a different key', () {
      final a = idempotencyKeyFor(file('a.mp4'), 'en', 'km');
      final b = idempotencyKeyFor(file('b.mp4'), 'en', 'km');
      expect(a, isNot(b));
    });
  });

  group('MIME types', () {
    test('each accepted extension maps to a media type', () {
      expect(mimeForFile('a.mp4'), 'video/mp4');
      expect(mimeForFile('a.mov'), 'video/quicktime');
      expect(mimeForFile('a.mp3'), 'audio/mpeg');
      expect(mimeForFile('a.wav'), 'audio/wav');
      expect(mimeForFile('a.m4a'), 'audio/mp4');
      expect(mimeForFile('A.MP4'), 'video/mp4');
    });
  });

  group('Size labels', () {
    test('formats KB, MB and GB', () {
      expect(file('a.mp4', size: 20 * 1024).sizeLabel, '20 KB');
      expect(file('a.mp4', size: 5 * 1024 * 1024).sizeLabel, '5.0 MB');
      expect(file('a.mp4', size: 2 * 1024 * 1024 * 1024).sizeLabel, '2.0 GB');
    });
  });
}