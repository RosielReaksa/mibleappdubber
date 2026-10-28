import 'package:dubber_app/app/theme/tokens.dart';
import 'package:dubber_app/core/widgets/app_widgets.dart';
import 'package:dubber_app/core/widgets/dubber_character.dart';
import 'package:dubber_app/core/widgets/status_chip.dart';
import 'package:dubber_app/features/projects/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: child),
    );

void main() {
  group('Queue screen states', () {
    testWidgets('loading shows a spinner', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty offers Add videos, not Start a new project',
        (tester) async {
      await tester.pumpWidget(wrap(StateView(
        title: 'Nothing in the queue',
        message: 'Add videos and they will dub one after another, while you '
            'keep using the app.',
        actionLabel: 'Add videos',
        onAction: () {},
      )));
      expect(find.text('Nothing in the queue'), findsOneWidget);
      expect(find.text('Add videos'), findsOneWidget);
      expect(find.text('Start a new project'), findsNothing);
      expect(find.byType(DubberCharacter), findsOneWidget);
    });

    testWidgets('error shows the message and a retry', (tester) async {
      await tester.pumpWidget(wrap(StateView(
        title: 'We could not load the queue',
        message: 'We could not reach the server. Check your connection.',
        mood: CharacterMood.worried,
        actionLabel: 'Try again',
        onAction: () {},
      )));
      expect(find.text('We could not load the queue'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline shows a calm message and a retry', (tester) async {
      await tester.pumpWidget(wrap(StateView(
        title: 'You are offline',
        message: 'We will pick up your queue when you reconnect.',
        mood: CharacterMood.worried,
        actionLabel: 'Try again',
        onAction: () {},
      )));
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Status chips', () {
    testWidgets('every state is icon + text', (tester) async {
      await tester.pumpWidget(wrap(Column(
        children: const [
          StatusPill(
            label: 'Dubbing 64%',
            background: Tokens.workingBg,
            foreground: Tokens.workingText,
            icon: Icons.autorenew_rounded,
          ),
          StatusPill(
            label: 'Waiting · 2',
            background: Tokens.oat,
            foreground: Tokens.clayDeep,
            icon: Icons.schedule_rounded,
          ),
          StatusPill(
            label: 'Failed',
            background: Tokens.softClay,
            foreground: Tokens.clayDeep,
            icon: Icons.warning_amber_rounded,
          ),
        ],
      )));

      expect(find.text('Dubbing 64%'), findsOneWidget);
      expect(find.text('Waiting · 2'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.byIcon(Icons.autorenew_rounded), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('Failed row contract', () {
    testWidgets('explains the reason and returns credits', (tester) async {
      await tester.pumpWidget(wrap(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Broken.mp4',
              style: AppText.label.copyWith(fontWeight: FontWeight.w600)),
          Text('That file type is not supported.', style: AppText.caption),
          Text('Credits returned', style: AppText.caption),
          TextButton(onPressed: () {}, child: const Text('Try again')),
        ],
      )));

      expect(find.text('That file type is not supported.'), findsOneWidget);
      expect(find.text('Credits returned'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('New screen button', () {
    testWidgets('one video: Start dubbing with its credits', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Start dubbing · 12 credits', onPressed: () {}),
      ));
      expect(find.text('Start dubbing · 12 credits'), findsOneWidget);
    });

    testWidgets('one video is never asked for a batch count', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Start dubbing', onPressed: () {}),
      ));
      expect(find.text('Start dubbing'), findsOneWidget);
      expect(find.textContaining('videos ·'), findsNothing);
    });

    testWidgets('blocked state offers a way to the Queue', (tester) async {
      await tester.pumpWidget(wrap(Row(
        children: [
          const Icon(Icons.schedule_rounded),
          const Expanded(
            child: Text(
              'A video is already dubbing. Add more videos from the Queue tab.',
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('Open Queue')),
        ],
      )));

      expect(find.textContaining('already dubbing'), findsOneWidget);
      expect(find.text('Open Queue'), findsOneWidget);
    });
  });

  group('Add videos footer', () {
    testWidgets('names the count and the total', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Add 3 videos · 36 credits', onPressed: () {}),
      ));
      expect(find.text('Add 3 videos · 36 credits'), findsOneWidget);
    });

    testWidgets('singular for one video', (tester) async {
      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Add 1 video · 12 credits', onPressed: () {}),
      ));
      expect(find.text('Add 1 video · 12 credits'), findsOneWidget);
    });

    testWidgets('a rejected file states why it is not added',
        (tester) async {
      await tester.pumpWidget(wrap(const Column(
        children: [
          Text('Broken.txt'),
          Text('This file type is not supported. Use MP4, MOV, MP3, WAV or M4A.',
              style: AppText.caption),
          Text('1 file will not be added. See its reason above.'),
        ],
      )));

      expect(find.textContaining('not supported'), findsOneWidget);
      expect(find.textContaining('will not be added'), findsOneWidget);
    });
  });
}