/// Domain models. Plain immutable classes with explicit JSON mapping.
library;

enum VideoFormat {
  landscape,
  portrait;

  String get wire => name;
  static VideoFormat fromWire(String? v) =>
      v == 'portrait' ? VideoFormat.portrait : VideoFormat.landscape;
}

enum VoiceChoice {
  female,
  male,
  auto;

  String get wire => name;
  static VoiceChoice fromWire(String? v) => switch (v) {
        'male' => VoiceChoice.male,
        'auto' => VoiceChoice.auto,
        _ => VoiceChoice.female,
      };
}

enum JobStatus {
  queued,
  uploading,
  processing,
  done,
  failed;

  static JobStatus fromWire(String? v) => switch (v) {
        'uploading' => JobStatus.uploading,
        'processing' => JobStatus.processing,
        'done' => JobStatus.done,
        'failed' => JobStatus.failed,
        _ => JobStatus.queued,
      };

  bool get isTerminal => this == done || this == failed;
  bool get isActive => this == queued || this == uploading || this == processing;
}

class AudioMix {
  const AudioMix({
    this.dubbedVoice = 100,
    this.originalVoice = 15,
    this.music = 80,
  });

  final int dubbedVoice;
  final int originalVoice;
  final int music;

  static const replaceVoice = AudioMix(dubbedVoice: 100, originalVoice: 0, music: 80);
  static const voiceOver = AudioMix(dubbedVoice: 100, originalVoice: 15, music: 80);
  static const keepOriginal = AudioMix(dubbedVoice: 100, originalVoice: 70, music: 80);

  AudioMix copyWith({int? dubbedVoice, int? originalVoice, int? music}) => AudioMix(
        dubbedVoice: dubbedVoice ?? this.dubbedVoice,
        originalVoice: originalVoice ?? this.originalVoice,
        music: music ?? this.music,
      );

  Map<String, dynamic> toJson() => {
        'dubbed_voice': dubbedVoice,
        'original_voice': originalVoice,
        'music': music,
      };

  factory AudioMix.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AudioMix();
    return AudioMix(
      dubbedVoice: (j['dubbed_voice'] as num?)?.toInt() ?? 100,
      originalVoice: (j['original_voice'] as num?)?.toInt() ?? 15,
      music: (j['music'] as num?)?.toInt() ?? 80,
    );
  }

  /// Name of the preset this mix matches, or null for a custom mix.
  String? get presetName {
    if (originalVoice == 0) return 'replace';
    if (originalVoice == 15) return 'voiceOver';
    if (originalVoice >= 70) return 'keepOriginal';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AudioMix &&
      other.dubbedVoice == dubbedVoice &&
      other.originalVoice == originalVoice &&
      other.music == music;

  @override
  int get hashCode => Object.hash(dubbedVoice, originalVoice, music);
}

class Language {
  const Language({required this.code, required this.name});
  final String code;
  final String name;

  factory Language.fromJson(Map<String, dynamic> j) => Language(
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );
}

class Voice {
  const Voice({required this.id, required this.name, this.gender});
  final String id;
  final String name;
  final String? gender;

  factory Voice.fromJson(Map<String, dynamic> j) => Voice(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        gender: j['gender'] as String?,
      );
}

class Project {
  const Project({
    required this.id,
    required this.title,
    required this.status,
    this.sourceLanguage,
    this.targetLanguage,
    this.format = VideoFormat.landscape,
    this.percent = 0,
    this.step,
    this.dubbedUrl,
    this.originalUrl,
    this.thumbnailUrl,
    this.createdAt,
    this.mix = const AudioMix(),
    this.voice = VoiceChoice.female,
    this.jobId,
    this.failReason,
    this.position,
    this.credits,
    this.startedAt,
  });

  final String id;
  final String title;
  final JobStatus status;
  final String? sourceLanguage;
  final String? targetLanguage;
  final VideoFormat format;
  final int percent;
  final String? step;
  final String? dubbedUrl;
  final String? originalUrl;
  final String? thumbnailUrl;
  final DateTime? createdAt;
  final AudioMix mix;
  final VoiceChoice voice;
  final String? jobId;
  final String? failReason;

  /// 1-based place in the waiting list; null while it is dubbing or idle.
  final int? position;

  /// Credits reserved when the job was added, returned if it fails.
  final int? credits;

  /// When the server began dubbing it.
  final DateTime? startedAt;

  bool get hasVideo => dubbedUrl != null;

  /// True while the job still belongs in the Queue.
  bool get isActive =>
      status == JobStatus.queued ||
      status == JobStatus.uploading ||
      status == JobStatus.processing;

  Project copyWith({
    JobStatus? status,
    int? percent,
    String? step,
    String? dubbedUrl,
    String? failReason,
    int? position,
  }) =>
      Project(
        id: id,
        title: title,
        status: status ?? this.status,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        format: format,
        percent: percent ?? this.percent,
        step: step ?? this.step,
        dubbedUrl: dubbedUrl ?? this.dubbedUrl,
        originalUrl: originalUrl,
        thumbnailUrl: thumbnailUrl,
        createdAt: createdAt,
        mix: mix,
        voice: voice,
        jobId: jobId,
        failReason: failReason ?? this.failReason,
        position: position ?? this.position,
        credits: credits,
        startedAt: startedAt,
      );

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? j['file_name'] as String? ?? 'Untitled',
        status: JobStatus.fromWire(j['status'] as String?),
        sourceLanguage: j['source_language'] as String?,
        targetLanguage: j['target_language'] as String?,
        format: VideoFormat.fromWire(j['format'] as String?),
        percent: (j['percent'] as num?)?.toInt() ?? 0,
        step: j['step'] as String?,
        dubbedUrl: j['dubbed_url'] as String?,
        originalUrl: j['original_url'] as String?,
        thumbnailUrl: j['thumbnail_url'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
        mix: AudioMix.fromJson(j['mix'] as Map<String, dynamic>?),
        voice: VoiceChoice.fromWire(j['voice'] as String?),
        jobId: j['job_id'] as String?,
        failReason: j['reason'] as String?,
        position: (j['position'] as num?)?.toInt(),
        credits: (j['credits'] as num?)?.toInt(),
        startedAt: DateTime.tryParse(j['started_at'] as String? ?? ''),
      );

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'source_language': sourceLanguage,
        'target_language': targetLanguage,
        'format': format.wire,
        'percent': percent,
        'step': step,
        'dubbed_url': dubbedUrl,
        'original_url': originalUrl,
        'thumbnail_url': thumbnailUrl,
        'created_at': createdAt?.toIso8601String(),
        'mix': mix.toJson(),
        'voice': voice.wire,
        'job_id': jobId,
        'reason': failReason,
        'position': position,
        'credits': credits,
        'started_at': startedAt?.toIso8601String(),
      };
}

class JobProgress {
  const JobProgress({
    required this.id,
    required this.status,
    required this.percent,
    this.step,
    this.steps = const [],
    this.reason,
  });

  final String id;
  final JobStatus status;
  final int percent;
  final String? step;
  final List<String> steps;
  final String? reason;

  factory JobProgress.fromJson(Map<String, dynamic> j) => JobProgress(
        id: j['id'] as String? ?? '',
        status: JobStatus.fromWire(j['status'] as String?),
        percent: (j['percent'] as num?)?.toInt() ?? 0,
        step: j['step'] as String?,
        steps: (j['steps'] as List?)?.cast<String>() ??
            const ['upload', 'transcribe', 'translate', 'generate_voice', 'mix_export'],
        reason: j['reason'] as String?,
      );
}

class CreditPack {
  const CreditPack({
    required this.id,
    required this.credits,
    required this.price,
    this.currency = r'$',
  });

  final String id;
  final int credits;
  final String price;
  final String currency;

  factory CreditPack.fromJson(Map<String, dynamic> j) => CreditPack(
        id: j['id'] as String? ?? '',
        credits: (j['credits'] as num?)?.toInt() ?? 0,
        price: j['price']?.toString() ?? '',
        currency: j['currency'] as String? ?? r'$',
      );
}

class Template {
  const Template({
    required this.id,
    required this.name,
    this.description = '',
    this.format,
    this.subtitleStyle,
    this.subtitlesOn = false,
    this.mix,
    this.fitMode,
    this.fitBlur,
    this.logoPosition,
  });

  final String id;
  final String name;
  final String description;
  final VideoFormat? format;
  final String? subtitleStyle;
  final bool subtitlesOn;
  final AudioMix? mix;
  final String? fitMode;
  final int? fitBlur;
  final String? logoPosition;

  factory Template.fromJson(Map<String, dynamic> j) {
    final s = (j['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final subs = (s['subtitles'] as Map?)?.cast<String, dynamic>();
    final fit = (s['fit'] as Map?)?.cast<String, dynamic>();
    return Template(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '',
      description: j['description'] as String? ?? '',
      format: s['format'] == null ? null : VideoFormat.fromWire(s['format'] as String?),
      subtitleStyle: subs?['style'] as String?,
      subtitlesOn: subs?['show'] as bool? ?? false,
      mix: (s['mix'] as Map?)?.cast<String, dynamic>() is Map<String, dynamic>
          ? AudioMix.fromJson((s['mix'] as Map).cast<String, dynamic>())
          : null,
      fitMode: fit?['mode'] as String?,
      fitBlur: (fit?['blur_strength'] as num?)?.toInt(),
      logoPosition: s['logo_position'] as String?,
    );
  }
}
