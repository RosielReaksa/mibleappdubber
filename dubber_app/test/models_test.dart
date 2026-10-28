import 'package:dubber_app/features/editor/application/editor_controller.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AudioMix', () {
    test('defaults match the spec', () {
      const mix = AudioMix();
      expect(mix.dubbedVoice, 100);
      expect(mix.originalVoice, 15);
      expect(mix.music, 80);
    });

    test('presets map to the right values', () {
      expect(AudioMix.replaceVoice.originalVoice, 0);
      expect(AudioMix.voiceOver.originalVoice, 15);
      expect(AudioMix.keepOriginal.originalVoice, 70);
    });

    test('presetName detects each preset', () {
      expect(AudioMix.replaceVoice.presetName, 'replace');
      expect(AudioMix.voiceOver.presetName, 'voiceOver');
      expect(AudioMix.keepOriginal.presetName, 'keepOriginal');
      expect(const AudioMix(originalVoice: 42).presetName, isNull);
    });

    test('serialises with snake_case keys', () {
      expect(const AudioMix().toJson(), {
        'dubbed_voice': 100,
        'original_voice': 15,
        'music': 80,
      });
    });

    test('round-trips through JSON', () {
      const original = AudioMix(dubbedVoice: 90, originalVoice: 20, music: 60);
      expect(AudioMix.fromJson(original.toJson()), original);
    });
  });

  group('EditorState → ExportSettings', () {
    test('all positions are fractions, never pixels', () {
      final state = const EditorState().copyWith(
        texts: const [
          TextOverlay(text: 'Hi', x: 0.5, y: 0.85),
        ],
      );
      final json = state.toExportSettings();
      final texts = json['texts'] as List;
      final first = texts.first as Map;
      expect(first['x'], 0.5);
      expect(first['y'], 0.85);
      expect(first['x'], lessThanOrEqualTo(1));
      expect(first['y'], lessThanOrEqualTo(1));
    });

    test('includes every export section', () {
      final json = const EditorState().toExportSettings();
      for (final key in [
        'format',
        'mix',
        'trim',
        'texts',
        'logos',
        'subtitles',
        'blurs',
        'fit',
        'filter',
      ]) {
        expect(json.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('enums serialise to their wire names', () {
      final state = const EditorState().copyWith(
        format: VideoFormat.portrait,
        subtitleStyle: SubtitleStyle.box,
        filter: FilterName.warm,
        fitMode: FitMode.bars,
      );
      final json = state.toExportSettings();
      expect(json['format'], 'portrait');
      expect((json['subtitles'] as Map)['style'], 'box');
      expect((json['filter'] as Map)['name'], 'warm');
      expect((json['fit'] as Map)['mode'], 'bars');
    });

    test('fit is only needed when formats differ', () {
      const same = EditorState(
        format: VideoFormat.landscape,
        sourceFormat: VideoFormat.landscape,
      );
      const different = EditorState(
        format: VideoFormat.portrait,
        sourceFormat: VideoFormat.landscape,
      );
      expect(same.needsFit, isFalse);
      expect(different.needsFit, isTrue);
    });

    test('logo is omitted when no asset is set', () {
      final json = const EditorState().toExportSettings();
      expect(json['logos'], isEmpty);
    });

    test('logo is included with a corner position once set', () {
      final state = const EditorState()
          .copyWith(logo: const LogoOverlay(assetId: 'logo_1'));
      final logos = state.toExportSettings()['logos'] as List;
      expect(logos, hasLength(1));
      expect((logos.first as Map)['position'], 'top_right');
    });
  });

  group('Project parsing', () {
    test('reads status, percent and languages', () {
      final project = Project.fromJson(const {
        'id': 'p1',
        'title': 'Demo.mp4',
        'status': 'processing',
        'percent': 64,
        'source_language': 'en',
        'target_language': 'km',
        'format': 'portrait',
      });
      expect(project.id, 'p1');
      expect(project.status, JobStatus.processing);
      expect(project.percent, 64);
      expect(project.format, VideoFormat.portrait);
      expect(project.status.isTerminal, isFalse);
    });

    test('done and failed are terminal', () {
      expect(JobStatus.done.isTerminal, isTrue);
      expect(JobStatus.failed.isTerminal, isTrue);
      expect(JobStatus.queued.isTerminal, isFalse);
    });

    test('cache JSON round-trips', () {
      final original = Project.fromJson(const {
        'id': 'p2',
        'title': 'A.mp4',
        'status': 'done',
        'percent': 100,
        'source_language': 'en',
        'target_language': 'es',
        'mix': {'dubbed_voice': 100, 'original_voice': 15, 'music': 80},
      });
      final restored = Project.fromJson(original.toCacheJson());
      expect(restored.id, original.id);
      expect(restored.status, original.status);
      expect(restored.mix, original.mix);
    });
  });

  group('Template → New project prefill', () {
    test('reads nested settings', () {
      final template = Template.fromJson(const {
        'id': 'tpl_short',
        'name': 'Short video',
        'description': 'For Reels.',
        'settings': {
          'format': 'portrait',
          'subtitles': {'show': true, 'style': 'bold'},
          'mix': {'dubbed_voice': 100, 'original_voice': 15, 'music': 80},
          'fit': {'mode': 'blur', 'blur_strength': 60},
          'logo_position': 'top_right',
        },
      });
      expect(template.format, VideoFormat.portrait);
      expect(template.subtitlesOn, isTrue);
      expect(template.subtitleStyle, 'bold');
      expect(template.mix?.originalVoice, 15);
      expect(template.fitMode, 'blur');
      expect(template.logoPosition, 'top_right');
    });
  });
}
