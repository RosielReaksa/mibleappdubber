import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dubber_app/core/api/api_error.dart';
import 'package:dubber_app/core/widgets/app_widgets.dart';
import 'package:dubber_app/features/library/sections/templates_section.dart';
import 'package:dubber_app/features/projects/domain/models.dart';

void main() {
  const templates = [
    Template(id: 'one', name: 'Short name', description: 'One line'),
    Template(id: 'two', name: 'Long template name', description: 'An intentionally long summary to verify that fixed card heights do not change when text wraps.', subtitlesOn: true, subtitleStyle: 'classic'),
  ];
  testWidgets('shows spinner while loading', (tester) async {
    await tester.pumpWidget(_app(const TemplatesBody(loading: true, hasCache: false, error: null, templates: [], offline: false, onRetry: _noop, onTap: _ignoreTemplate)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
  testWidgets('shows empty title and refresh action', (tester) async {
    await tester.pumpWidget(_app(const TemplatesBody(loading: false, hasCache: false, error: null, templates: [], offline: false, onRetry: _noop, onTap: _ignoreTemplate)));
    expect(find.text('No templates yet'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
  testWidgets('shows error message and retry action', (tester) async {
    await tester.pumpWidget(_app(const TemplatesBody(loading: false, hasCache: false, error: ApiError(code: 'failure', message: 'Network trouble'), templates: [], offline: false, onRetry: _noop, onTap: _ignoreTemplate)));
    expect(find.text('Network trouble'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
  testWidgets('cards with different summary lengths have equal heights', (tester) async {
    await tester.pumpWidget(_app(TemplatesCards(templates: templates, offline: false, onRefresh: _noop, onTap: _ignoreTemplate)));
    final cards = find.byType(AppCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getSize(cards.at(0)).height, tester.getSize(cards.at(1)).height);
  });
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));
void _noop() {}
void _ignoreTemplate(Template template) {}
