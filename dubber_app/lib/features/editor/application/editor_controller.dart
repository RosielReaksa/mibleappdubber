import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/domain/models.dart';

enum EditorTool { text, logo, subtitles, trim, audio, blur, fit, filters }

enum SubtitleStyle { classic, bold, box }

enum BlurSide { top, bottom, left, right }

enum BlurStyle { blur, pixelate }

enum FitMode { blur, bars, fill }

enum FilterName { none, warm, cool, mono, vivid, soft }

enum LogoPosition { topLeft, topRight, bottomLeft, bottomRight }

/// One text overlay. Positions are fractions 0..1, never pixels.
class TextOverlay {
  const TextOverlay({
    this.text = '',
    this.size = 60,
    this.color = '#FFFFFF',
    this.x = 0.5,
    this.y = 0.85,
    this.from = 0,
    this.to = 90,
  });

  final String text;
  final int size;
  final String color;
  final double x;
  final double y;
  final double from;
  final double to;

  TextOverlay copyWith({
    String? text,
    int? size,
    String? color,
    double? x,
    double? y,
    double? from,
    double? to,
  }) =>
      TextOverlay(
        text: text ?? this.text,
        size: size ?? this.size,
        color: color ?? this.color,
        x: x ?? this.x,
        y: y ?? this.y,
        from: from ?? this.from,
        to: to ?? this.to,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'size': size,
        'color': color,
        'x': x,
        'y': y,
        'from': from,
        'to': to,
      };
}

class LogoOverlay {
  const LogoOverlay({
    this.assetId,
    this.size = 40,
    this.opacity = 90,
    this.position = LogoPosition.topRight,
    this.from = 0,
    this.to = 90,
  });

  final String? assetId;
  final int size;
  final int opacity;
  final LogoPosition position;
  final double from;
  final double to;

  String get positionWire => switch (position) {
        LogoPosition.topLeft => 'top_left',
        LogoPosition.topRight => 'top_right',
        LogoPosition.bottomLeft => 'bottom_left',
        LogoPosition.bottomRight => 'bottom_right',
      };

  LogoOverlay copyWith({
    String? assetId,
    int? size,
    int? opacity,
    LogoPosition? position,
  }) =>
      LogoOverlay(
        assetId: assetId ?? this.assetId,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
        position: position ?? this.position,
        from: from,
        to: to,
      );

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'size': size,
        'opacity': opacity,
        'position': positionWire,
        'from': from,
        'to': to,
      };
}

class BlurOverlay {
  const BlurOverlay({
    this.sides = const {BlurSide.top, BlurSide.bottom},
    this.thickness = 30,
    this.strength = 60,
    this.style = BlurStyle.blur,
    this.from = 0,
    this.to = 90,
  });

  final Set<BlurSide> sides;
  final int thickness;
  final int strength;
  final BlurStyle style;
  final double from;
  final double to;

  BlurOverlay copyWith({
    Set<BlurSide>? sides,
    int? thickness,
    int? strength,
    BlurStyle? style,
  }) =>
      BlurOverlay(
        sides: sides ?? this.sides,
        thickness: thickness ?? this.thickness,
        strength: strength ?? this.strength,
        style: style ?? this.style,
        from: from,
        to: to,
      );

  Map<String, dynamic> toJson() => {
        'sides': sides.map((s) => s.name).toList(),
        'thickness': thickness,
        'strength': strength,
        'style': style.name,
        'from': from,
        'to': to,
      };
}

/// The whole editor state. Maps 1:1 to the export payload.
class EditorState {
  const EditorState({
    this.format = VideoFormat.landscape,
    this.sourceFormat = VideoFormat.landscape,
    this.tool = EditorTool.text,
    this.mix = const AudioMix(),
    this.trimStart = 0,
    this.trimEnd = 90,
    this.texts = const [],
    this.logo = const LogoOverlay(),
    this.subtitlesOn = true,
    this.subtitleStyle = SubtitleStyle.classic,
    this.subtitleSize = 55,
    this.blurs = const [],
    this.fitMode = FitMode.blur,
    this.fitBlurStrength = 60,
    this.filter = FilterName.none,
    this.filterStrength = 70,
    this.dirty = false,
    this.saving = false,
    this.exporting = false,
    this.error,
  });

  final VideoFormat format;
  final VideoFormat sourceFormat;
  final EditorTool tool;
  final AudioMix mix;
  final double trimStart;
  final double trimEnd;
  final List<TextOverlay> texts;
  final LogoOverlay logo;
  final bool subtitlesOn;
  final SubtitleStyle subtitleStyle;
  final int subtitleSize;
  final List<BlurOverlay> blurs;
  final FitMode fitMode;
  final int fitBlurStrength;
  final FilterName filter;
  final int filterStrength;
  final bool dirty;
  final bool saving;
  final bool exporting;
  final String? error;

  /// Fit only matters when the export format differs from the source.
  bool get needsFit => format != sourceFormat;

  EditorState copyWith({
    VideoFormat? format,
    VideoFormat? sourceFormat,
    EditorTool? tool,
    AudioMix? mix,
    double? trimStart,
    double? trimEnd,
    List<TextOverlay>? texts,
    LogoOverlay? logo,
    bool? subtitlesOn,
    SubtitleStyle? subtitleStyle,
    int? subtitleSize,
    List<BlurOverlay>? blurs,
    FitMode? fitMode,
    int? fitBlurStrength,
    FilterName? filter,
    int? filterStrength,
    bool? dirty,
    bool? saving,
    bool? exporting,
    String? error,
    bool clearError = false,
  }) =>
      EditorState(
        format: format ?? this.format,
        sourceFormat: sourceFormat ?? this.sourceFormat,
        tool: tool ?? this.tool,
        mix: mix ?? this.mix,
        trimStart: trimStart ?? this.trimStart,
        trimEnd: trimEnd ?? this.trimEnd,
        texts: texts ?? this.texts,
        logo: logo ?? this.logo,
        subtitlesOn: subtitlesOn ?? this.subtitlesOn,
        subtitleStyle: subtitleStyle ?? this.subtitleStyle,
        subtitleSize: subtitleSize ?? this.subtitleSize,
        blurs: blurs ?? this.blurs,
        fitMode: fitMode ?? this.fitMode,
        fitBlurStrength: fitBlurStrength ?? this.fitBlurStrength,
        filter: filter ?? this.filter,
        filterStrength: filterStrength ?? this.filterStrength,
        dirty: dirty ?? this.dirty,
        saving: saving ?? this.saving,
        exporting: exporting ?? this.exporting,
        error: clearError ? null : (error ?? this.error),
      );

  /// The payload sent to `POST /projects/{id}/exports`.
  Map<String, dynamic> toExportSettings() => {
        'format': format.wire,
        'mix': mix.toJson(),
        'trim': {'start': trimStart, 'end': trimEnd},
        'texts': texts.map((t) => t.toJson()).toList(),
        'logos': logo.assetId == null ? [] : [logo.toJson()],
        'subtitles': {
          'show': subtitlesOn,
          'style': subtitleStyle.name,
          'size': subtitleSize,
        },
        'blurs': blurs.map((b) => b.toJson()).toList(),
        'fit': {'mode': fitMode.name, 'blur_strength': fitBlurStrength},
        'filter': {'name': filter.name, 'strength': filterStrength},
      };
}

class EditorController extends StateNotifier<EditorState> {
  EditorController(this._ref, this.projectId) : super(const EditorState());

  final Ref _ref;
  final String projectId;

  void selectTool(EditorTool tool) => state = state.copyWith(tool: tool);

  void setFormat(VideoFormat format) =>
      state = state.copyWith(format: format, dirty: true);

  void setMix(AudioMix mix) => state = state.copyWith(mix: mix, dirty: true);

  void setTrim({double? start, double? end}) => state = state.copyWith(
        trimStart: start,
        trimEnd: end,
        dirty: true,
      );

  void setSubtitles({bool? show, SubtitleStyle? style, int? size}) =>
      state = state.copyWith(
        subtitlesOn: show,
        subtitleStyle: style,
        subtitleSize: size,
        dirty: true,
      );

  void setText(TextOverlay text) {
    final list = [...state.texts];
    if (list.isEmpty) {
      list.add(text);
    } else {
      list[0] = text;
    }
    state = state.copyWith(texts: list, dirty: true);
  }

  void moveText({required double x, required double y}) {
    if (state.texts.isEmpty) return;
    setText(state.texts.first.copyWith(
      x: x.clamp(0.0, 1.0),
      y: y.clamp(0.0, 1.0),
    ));
  }

  void setLogo(LogoOverlay logo) =>
      state = state.copyWith(logo: logo, dirty: true);

  void setBlur(BlurOverlay blur) {
    final list = [...state.blurs];
    if (list.isEmpty) {
      list.add(blur);
    } else {
      list[0] = blur;
    }
    state = state.copyWith(blurs: list, dirty: true);
  }

  void addBlur() {
    state = state.copyWith(
      blurs: [...state.blurs, const BlurOverlay()],
      dirty: true,
    );
  }

  void setFit({FitMode? mode, int? blurStrength}) => state = state.copyWith(
        fitMode: mode,
        fitBlurStrength: blurStrength,
        dirty: true,
      );

  void setFilter({FilterName? name, int? strength}) => state = state.copyWith(
        filter: name,
        filterStrength: strength,
        dirty: true,
      );

  void markSaved() => state = state.copyWith(dirty: false);
  void setSaving(bool v) => state = state.copyWith(saving: v);
  void setExporting(bool v) => state = state.copyWith(exporting: v);
  void setError(String? message) =>
      state = state.copyWith(error: message, exporting: false);
}

final editorControllerProvider =
    StateNotifierProvider.family<EditorController, EditorState, String>(
  (ref, projectId) => EditorController(ref, projectId),
);
