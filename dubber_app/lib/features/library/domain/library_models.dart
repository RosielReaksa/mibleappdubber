/// Library items: saved logos, saved text/subtitle styles, and presets.
///
/// All three are plain immutable values with explicit JSON mapping, so the
/// API layer and the local cache can share them.
library;

import '../../editor/application/editor_controller.dart';
import '../../projects/domain/models.dart';

// ── Logos ─────────────────────────────────────────────────────────────────

/// A logo the user saved. The bytes live on the server; the app only needs
/// the id and a name to show it in a grid and to attach it to an export.
class SavedLogo {
  const SavedLogo({
    required this.id,
    required this.name,
    this.url,
    this.createdAt,
  });

  final String id;
  final String name;

  /// Thumbnail / full image URL, when the server returns one.
  final String? url;
  final DateTime? createdAt;

  factory SavedLogo.fromJson(Map<String, dynamic> j) => SavedLogo(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Logo',
        url: (j['url'] ?? j['image_url'] ?? j['download_url']) as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'created_at': createdAt?.toIso8601String(),
      };

  SavedLogo copyWith({String? name, String? url}) => SavedLogo(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        createdAt: createdAt,
      );
}

// ── Styles ────────────────────────────────────────────────────────────────

/// What a saved style applies to: a text overlay or the subtitles.
enum StyleKind { text, subtitle }

/// A saved text or subtitle style. Exactly the fields the editor tools expose.
class SavedStyle {
  const SavedStyle({
    required this.id,
    required this.name,
    required this.kind,
    this.size = 55,
    this.color = '#FFFFFF',
    this.subtitleStyle = SubtitleStyle.classic,
    this.createdAt,
  });

  final String id;
  final String name;
  final StyleKind kind;

  /// Font size in the editor's 0..100 scale for subtitles, or the text
  /// overlay's size value for text.
  final int size;

  /// Hex string like `#FFFFFF`. Only meaningful for [StyleKind.text].
  final String color;

  /// Only meaningful for [StyleKind.subtitle].
  final SubtitleStyle subtitleStyle;

  final DateTime? createdAt;

  static const defaultTextSize = 60;
  static const defaultSubtitleSize = 55;

  /// A style built from what the editor currently shows, so "Save as style"
  /// stores exactly the user's settings.
  factory SavedStyle.fromEditor({
    required String id,
    required String name,
    required EditorState state,
  }) =>
      state.tool == EditorTool.subtitles
          ? SavedStyle(
              id: id,
              name: name,
              kind: StyleKind.subtitle,
              size: state.subtitleSize,
              subtitleStyle: state.subtitleStyle,
            )
          : SavedStyle(
              id: id,
              name: name,
              kind: StyleKind.text,
              size: state.texts.isEmpty
                  ? defaultTextSize
                  : state.texts.first.size,
              color: state.texts.isEmpty
                  ? '#FFFFFF'
                  : state.texts.first.color,
            );

  factory SavedStyle.fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind'] as String?) {
      'subtitle' => StyleKind.subtitle,
      _ => StyleKind.text,
    };
    final subs = (j['subtitle_style'] as String?) ?? (j['style'] as String?);
    return SavedStyle(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Style',
      kind: kind,
      size: (j['size'] as num?)?.toInt() ??
          (kind == StyleKind.subtitle ? defaultSubtitleSize : defaultTextSize),
      color: j['color'] as String? ?? '#FFFFFF',
      subtitleStyle: switch (subs) {
        'bold' => SubtitleStyle.bold,
        'box' => SubtitleStyle.box,
        _ => SubtitleStyle.classic,
      },
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'size': size,
        'color': color,
        'subtitle_style': subtitleStyle.name,
        'created_at': createdAt?.toIso8601String(),
      };

  SavedStyle copyWith({
    String? name,
    int? size,
    String? color,
    SubtitleStyle? subtitleStyle,
  }) =>
      SavedStyle(
        id: id,
        name: name ?? this.name,
        kind: kind,
        size: size ?? this.size,
        color: color ?? this.color,
        subtitleStyle: subtitleStyle ?? this.subtitleStyle,
        createdAt: createdAt,
      );

  /// One-line summary for the Library list, e.g. "Bold · 55" or "#FFFFFF · 60".
  String get summary => kind == StyleKind.subtitle
      ? '${_cap(subtitleStyle.name)} · $size'
      : '$color · $size';

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ── Presets ───────────────────────────────────────────────────────────────

/// A user-made template: the same settings a Dubber template carries.
///
/// [template] is the prefill payload the New project screen already knows how
/// to apply, so a preset behaves exactly like a server template.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.template,
    this.createdAt,
  });

  final String id;
  final String name;

  /// The settings this preset stands for, in template shape.
  final Template template;
  final DateTime? createdAt;

  /// Builds a preset from the New project form.
  factory Preset.fromNewProject({
    required String id,
    required String name,
    required VideoFormat format,
    required AudioMix mix,
    String? subtitleStyle,
    bool subtitlesOn = false,
    String? fitMode,
    int? fitBlur,
    String? logoPosition,
  }) =>
      Preset(
        id: id,
        name: name,
        template: Template(
          id: id,
          name: name,
          description: 'Your preset',
          format: format,
          mix: mix,
          subtitleStyle: subtitleStyle,
          subtitlesOn: subtitlesOn,
          fitMode: fitMode,
          fitBlur: fitBlur,
          logoPosition: logoPosition,
        ),
      );

  factory Preset.fromJson(Map<String, dynamic> j) {
    final settings =
        (j['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Preset(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? 'Preset',
      template: Template.fromJson({
        'id': j['id'],
        'name': j['name'],
        'description': j['description'] ?? 'Your preset',
        'settings': settings,
      }),
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'settings': {
          if (template.format != null) 'format': template.format!.wire,
          'subtitles': {
            'show': template.subtitlesOn,
            if (template.subtitleStyle != null)
              'style': template.subtitleStyle,
          },
          if (template.mix != null) 'mix': template.mix!.toJson(),
          if (template.fitMode != null)
            'fit': {
              'mode': template.fitMode,
              if (template.fitBlur != null) 'blur_strength': template.fitBlur,
            },
          if (template.logoPosition != null)
            'logo_position': template.logoPosition,
        },
        'created_at': createdAt?.toIso8601String(),
      };

  Preset copyWith({String? name}) => Preset(
        id: id,
        name: name ?? this.name,
        template: template,
        createdAt: createdAt,
      );
}