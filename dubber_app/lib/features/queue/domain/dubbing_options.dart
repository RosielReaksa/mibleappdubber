import '../../projects/domain/models.dart';
import 'queue_rules.dart';

/// The dubbing settings for one added video.
///
/// Every video in an add starts with the same settings; the user may change
/// any of them for one video without touching the rest.
class DubbingOptions {
  const DubbingOptions({
    required this.sourceCode,
    required this.targetCode,
    this.format = VideoFormat.landscape,
    this.voice = VoiceChoice.female,
    this.mix = const AudioMix(),
    this.templateId,
  });

  final String sourceCode;
  final String targetCode;
  final VideoFormat format;
  final VoiceChoice voice;
  final AudioMix mix;
  final String? templateId;

  DubbingOptions copyWith({
    String? sourceCode,
    String? targetCode,
    VideoFormat? format,
    VoiceChoice? voice,
    AudioMix? mix,
    String? templateId,
  }) =>
      DubbingOptions(
        sourceCode: sourceCode ?? this.sourceCode,
        targetCode: targetCode ?? this.targetCode,
        format: format ?? this.format,
        voice: voice ?? this.voice,
        mix: mix ?? this.mix,
        templateId: templateId ?? this.templateId,
      );

  /// The body the queue endpoint expects for one video.
  Map<String, dynamic> toItemJson(PickedFile file) => {
        'file_name': file.name,
        'source_language': sourceCode,
        'target_language': targetCode,
        'format': format.wire,
        'voice': voice.wire,
        'mix': mix.toJson(),
        if (templateId != null) 'template_id': templateId,
        'idempotency_key': idempotencyKeyFor(file, sourceCode, targetCode),
      };
}