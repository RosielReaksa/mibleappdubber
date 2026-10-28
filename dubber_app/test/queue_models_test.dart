import 'package:dubber_app/features/projects/data/dubber_api.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:dubber_app/features/queue/domain/dubbing_options.dart';
import 'package:dubber_app/features/queue/domain/queue_rules.dart';
import 'package:flutter_test/flutter_test.dart';

PickedFile file(String name) =>
    PickedFile(name: name, size: 1024, path: '/tmp/$name');

void main() {
  group('QueueAddResponse parsing', () {
    test('reads now dubbing, the waiting list and rejected items', () {
      final response = QueueAddResponse.fromJson({
        'now_dubbing': {
          'id': 'p1',
          'title': 'One.mp4',
          'status': 'processing',
          'percent': 4,
        },
        'up_next': [
          {'id': 'p2', 'title': 'Two.mp4', 'status': 'queued', 'position': 1},
          {'id': 'p3', 'title': 'Three.mp4', 'status': 'queued', 'position': 2},
        ],
        'rejected': [
          {
            'file_name': 'Bad.txt',
            'code': 'unsupported_file',
            'message': 'That file type is not supported.',
          },
        ],
        'reserved_credits': 24,
        'balance': 96,
        'stopped_reason': 'not_enough_credits',
      });

      expect(response.nowDubbing!.title, 'One.mp4');
      expect(response.upNext.length, 2);
      expect(response.upNext[1].position, 2);
      expect(response.rejected.single.fileName, 'Bad.txt');
      expect(response.reservedCredits, 24);
      expect(response.balance, 96);
      expect(response.stoppedReason, 'not_enough_credits');
      // `added` includes the job that started plus everything waiting.
      expect(response.added.length, 3);
    });

    test('an empty answer adds nothing and says nothing', () {
      final response = QueueAddResponse.fromJson({});
      expect(response.nowDubbing, isNull);
      expect(response.upNext, isEmpty);
      expect(response.rejected, isEmpty);
      expect(response.added, isEmpty);
    });
  });

  group('Project parsing for the queue', () {
    test('reads position, credits and start time', () {
      final project = Project.fromJson({
        'id': 'p9',
        'title': 'Lesson.mp4',
        'status': 'queued',
        'position': 3,
        'credits': 12,
        'started_at': '2026-10-26T10:00:00Z',
      });
      expect(project.position, 3);
      expect(project.credits, 12);
      expect(project.startedAt, isNotNull);
      expect(project.isActive, isTrue);
    });

    test('a finished project is not active', () {
      final project = Project.fromJson({'id': 'p', 'status': 'done'});
      expect(project.isActive, isFalse);
    });

    test('a failed project is not active, so it leaves the waiting list', () {
      final project = Project.fromJson({'id': 'p', 'status': 'failed'});
      expect(project.isActive, isFalse);
    });

    test('copyWith moves a project to a new position', () {
      final project = Project.fromJson({'id': 'p', 'status': 'queued'});
      expect(project.copyWith(position: 1).position, 1);
    });
  });

  group('DubbingOptions', () {
    test('serialises to the shape the queue endpoint expects', () {
      const options = DubbingOptions(
        sourceCode: 'en',
        targetCode: 'km',
        format: VideoFormat.portrait,
        voice: VoiceChoice.male,
      );
      final json = options.toItemJson(file('a.mp4'));

      expect(json['file_name'], 'a.mp4');
      expect(json['source_language'], 'en');
      expect(json['target_language'], 'km');
      expect(json['format'], 'portrait');
      expect(json['voice'], 'male');
      expect(json['idempotency_key'], isA<String>());
      expect(json.containsKey('template_id'), isFalse);
    });

    test('carries a template when one was chosen', () {
      const options = DubbingOptions(
        sourceCode: 'en',
        targetCode: 'km',
        templateId: 'tpl_news',
      );
      expect(options.toItemJson(file('a.mp4'))['template_id'], 'tpl_news');
    });

    test('per-video options change only the field that was set', () {
      const base = DubbingOptions(sourceCode: 'en', targetCode: 'km');
      final changed = base.copyWith(targetCode: 'es');
      expect(changed.sourceCode, 'en');
      expect(changed.targetCode, 'es');
      expect(changed.format, base.format);
      expect(changed.voice, base.voice);
    });

    test('the same file with the same settings gives the same key twice', () {
      const options = DubbingOptions(sourceCode: 'en', targetCode: 'km');
      expect(
        options.toItemJson(file('a.mp4'))['idempotency_key'],
        options.toItemJson(file('a.mp4'))['idempotency_key'],
      );
    });
  });
}