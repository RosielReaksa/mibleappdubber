import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/api/api_error.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/dubber_character.dart';
import '../../../core/widgets/status_chip.dart';
import '../../projects/domain/models.dart';
import '../widgets/library_widgets.dart';

/// Library section showing reusable project templates.
class TemplatesSection extends ConsumerStatefulWidget {
  const TemplatesSection({super.key});

  @override
  ConsumerState<TemplatesSection> createState() => _TemplatesSectionState();
}

class _TemplatesSectionState extends ConsumerState<TemplatesSection> {
  static const _cacheKey = 'library_templates_v1';
  List<Template> _templates = const [];
  bool _loading = true;
  bool _hasCache = false;
  bool _offline = false;
  ApiError? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadCache() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return;
      final items = (jsonDecode(raw) as List)
          .map((item) => Template.fromJson((item as Map).cast<String, dynamic>()))
          .toList();
      if (mounted) setState(() { _templates = items; _hasCache = true; });
    } catch (_) {
      // A corrupt cache is replaced by the next successful refresh.
    }
  }

  Future<void> _saveCache(List<Template> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(templates.map(_toJson).toList()));
  }

  Map<String, dynamic> _toJson(Template t) => {
        'id': t.id,
        'name': t.name,
        'description': t.description,
        'settings': {
          if (t.format != null) 'format': t.format!.wire,
          'subtitles': {'show': t.subtitlesOn, 'style': t.subtitleStyle},
          'mix': t.mix?.toJson(),
          'fit': {'mode': t.fitMode, 'blur_strength': t.fitBlur},
          'logo_position': t.logoPosition,
        },
      };

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    await _loadCache();
    try {
      final templates = await ref.read(apiProvider).templates();
      if (!mounted) return;
      await _saveCache(templates);
      setState(() { _templates = templates; _loading = false; _hasCache = true; _offline = false; });
    } catch (e) {
      if (!mounted) return;
      final error = e is ApiError ? e : const ApiError.unknown();
      final offline = error.code == 'offline' || error.code == 'connection_lost' || error.code == 'timeout';
      setState(() {
        _loading = false;
        _error = offline && _hasCache ? null : error;
        _offline = offline && _hasCache;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TemplatesBody(
      loading: _loading,
      hasCache: _hasCache,
      error: _error,
      templates: _templates,
      offline: _offline,
      onRetry: _load,
      onTap: _showSheet,
    );
  }

  void _showSheet(Template template) {
    showModalBottomSheet<void>(context: context, backgroundColor: Tokens.ivory,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _TemplateSheet(template: template));
  }
}

/// State-aware body that keeps the section presentation independently testable.
class TemplatesBody extends StatelessWidget {
  const TemplatesBody({
    super.key,
    required this.loading,
    required this.hasCache,
    required this.error,
    required this.templates,
    required this.offline,
    required this.onRetry,
    required this.onTap,
  });

  final bool loading;
  final bool hasCache;
  final ApiError? error;
  final List<Template> templates;
  final bool offline;
  final VoidCallback onRetry;
  final ValueChanged<Template> onTap;

  @override
  Widget build(BuildContext context) {
    if (loading && !hasCache) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (error != null) {
      return StateView(
        title: 'We could not load templates',
        message: error!.message,
        mood: CharacterMood.worried,
        actionLabel: 'Try again',
        onAction: onRetry,
        compact: true,
      );
    }
    if (templates.isEmpty) {
      return StateView(
        title: 'No templates yet',
        message: 'Templates will appear here when they are available.',
        actionLabel: 'Refresh',
        onAction: onRetry,
        compact: true,
      );
    }
    return TemplatesCards(
      templates: templates,
      offline: offline,
      onTap: onTap,
      onRefresh: onRetry,
    );
  }
}

/// Fixed-height template grid and its companion navigation actions.
class TemplatesCards extends StatelessWidget {
  const TemplatesCards({super.key, required this.templates, required this.onTap, required this.offline, required this.onRefresh});

  final List<Template> templates;
  final ValueChanged<Template> onTap;
  final bool offline;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (offline) const OfflineBanner(),
          if (offline) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onRefresh, child: const Text('Refresh'))),
          Text('Pick a style and your project starts with the format, subtitles, and sound mix already set.', style: AppText.bodyMuted),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: templates.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: 176),
            itemBuilder: (context, i) => _TemplateCard(template: templates[i], onTap: () => onTap(templates[i])),
          ),
          const SizedBox(height: 20),
          NeutralButton(label: 'Watch the Quick guide', onPressed: () => context.push('/onboarding')),
          const SizedBox(height: 12),
          NeutralButton(label: 'Learn the editor', onPressed: () => context.push('/learn')),
        ],
      );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final Template template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: 'Template ${template.name}',
        child: GestureDetector(
          onTap: onTap,
          child: AppCard(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 86, width: double.infinity, child: Container(
                decoration: BoxDecoration(color: Tokens.oat, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.bottomLeft, padding: const EdgeInsets.all(8),
                child: Icon(template.format == VideoFormat.portrait ? Icons.crop_portrait_rounded : Icons.crop_landscape_rounded, color: Tokens.muted),
              )),
              const SizedBox(height: 8),
              SizedBox(height: 17, child: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(fontWeight: FontWeight.w600))),
              const SizedBox(height: 2),
              SizedBox(height: 30, child: Text(_summary(template), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.caption)),
            ],
          )),
        ),
      );

  String _summary(Template t) {
    final format = t.format == VideoFormat.portrait ? 'Portrait' : 'Landscape';
    final subs = t.subtitlesOn ? '${_cap(t.subtitleStyle ?? 'classic')} subtitles' : 'No subtitles';
    return '$format · $subs';
  }
  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _TemplateSheet extends StatelessWidget {
  const _TemplateSheet({required this.template});
  final Template template;

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tokens.borderStrong, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(template.name, style: AppText.sheetTitle()), const SizedBox(height: 4),
          Text(template.description, style: AppText.bodyMuted), const SizedBox(height: 12),
          _kv('Format', template.format == VideoFormat.portrait ? 'Portrait 9:16' : 'Landscape 16:9'),
          _kv('Subtitles', template.subtitlesOn ? '${_cap(template.subtitleStyle ?? 'classic')}, on' : 'Off'),
          _kv('Audio mix', _mixName(template.mix)), _kv('Fit', _fitName(template.fitMode)),
          _kv('Logo', _logoName(template.logoPosition), last: true), const SizedBox(height: 8),
          Text('You can change everything on the next screen.', style: AppText.caption), const SizedBox(height: 16),
          PrimaryButton(label: 'Use this template', onPressed: () { Navigator.pop(context); context.go('/new?template=${template.id}'); }),
        ]),
      ));

  Widget _kv(String key, String value, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Tokens.border))),
        child: Row(children: [Text(key, style: AppText.labelMuted), const Spacer(), Text(value, style: AppText.label.copyWith(fontWeight: FontWeight.w600))]),
      );
  String _mixName(AudioMix? mix) => switch (mix?.presetName) {'replace' => 'Replace voice', 'keepOriginal' => 'Keep original', _ => 'Voice-over'};
  String _fitName(String? mode) => switch (mode) {'bars' => 'Black bars', 'fill' => 'Fill screen', _ => 'Blurred background'};
  String _logoName(String? position) => switch (position) {'top_left' => 'Top left', 'bottom_left' => 'Bottom left', 'bottom_right' => 'Bottom right', _ => 'Top right'};
  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
