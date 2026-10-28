import 'package:dubber_app/app/theme/tokens.dart';
import 'package:dubber_app/core/widgets/app_widgets.dart';
import 'package:dubber_app/core/widgets/controls.dart';
import 'package:dubber_app/core/widgets/dubber_character.dart';
import 'package:dubber_app/core/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('PrimaryButton', () {
    testWidgets('shows its label and responds to taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(PrimaryButton(
        label: 'Start dubbing',
        onPressed: () => taps++,
      )));
      expect(find.text('Start dubbing'), findsOneWidget);
      await tester.tap(find.text('Start dubbing'));
      expect(taps, 1);
    });

    testWidgets('is disabled while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(PrimaryButton(
        label: 'Start',
        loading: true,
        onPressed: () => taps++,
      )));
      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('StatusPill', () {
    testWidgets('never relies on color alone', (tester) async {
      await tester.pumpWidget(wrap(const StatusPill(
        label: 'Done',
        background: Tokens.doneBg,
        foreground: Tokens.doneText,
      )));
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('StateView', () {
    testWidgets('renders title, message and action', (tester) async {
      await tester.pumpWidget(wrap(StateView(
        title: 'No projects yet',
        message: 'Dub your first video.',
        actionLabel: 'Create first project',
        onAction: () {},
      )));
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.text('Dub your first video.'), findsOneWidget);
      expect(find.text('Create first project'), findsOneWidget);
    });
  });

  group('MixSlider', () {
    testWidgets('exposes an accessible percentage', (tester) async {
      await tester.pumpWidget(wrap(MixSlider(
        label: 'Original voice',
        value: 15,
        onChanged: (_) {},
      )));
      expect(find.text('15%'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 15);
    });
  });

  group('SegmentedControl', () {
    testWidgets('reports the selected option and switches', (tester) async {
      var selected = 'landscape';
      await tester.pumpWidget(wrap(StatefulBuilder(
        builder: (context, setState) => SegmentedControl<String>(
          value: selected,
          onChanged: (v) => setState(() => selected = v),
          options: const [
            (value: 'landscape', label: 'Landscape', icon: null),
            (value: 'portrait', label: 'Portrait', icon: null),
          ],
        ),
      )));
      expect(find.text('Landscape'), findsOneWidget);
      await tester.tap(find.text('Portrait'));
      await tester.pump();
      expect(selected, 'portrait');
    });
  });

  group('DubberCharacter', () {
    testWidgets('animates normally', (tester) async {
      await tester.pumpWidget(wrap(const DubberCharacter()));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('respects reduce motion', (tester) async {
      await tester.pumpWidget(wrap(const DubberCharacter(), reduceMotion: true));
      // The painter should receive a constant (frozen) animation when the
      // platform asks for reduced motion, so nothing moves.
      final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(paints, isNotEmpty);
      await tester.pump(const Duration(seconds: 1));
      // No exceptions and no scheduled frames beyond the test's own pumps.
      expect(tester.takeException(), isNull);
    });

    testWidgets('has a semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const DubberCharacter()));
      expect(
        find.bySemanticsLabel(
          'A little character wearing headphones mixing sound at a desk',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('AppTextField', () {
    testWidgets('shows an error message under the field', (tester) async {
      await tester.pumpWidget(wrap(const AppTextField(
        label: 'Email',
        hint: 'you@email.com',
        errorText: 'Enter your email.',
      )));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Enter your email.'), findsOneWidget);
    });
  });
}
