import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/tokens.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/dubber_character.dart';

/// The four-page Quick guide shown on first launch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const seenKey = 'seenOnboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _GuidePage(
      title: 'Upload your video',
      body:
          'Choose any video or audio from your phone. Long files are fine, and your upload continues if your connection drops.',
      illustration: _Illustration.upload,
    ),
    _GuidePage(
      title: 'Pick language and voice',
      body:
          "Choose the language you want. Then pick a female voice, a male voice, or let the app detect the speaker's gender.",
      illustration: _Illustration.voice,
    ),
    _GuidePage(
      title: 'Make it yours',
      body:
          'Add text, your logo, subtitles, or blur an old subtitle. Move the music and voice up or down.',
      illustration: _Illustration.edit,
    ),
    _GuidePage(
      title: 'Export and share',
      body:
          'Download your finished video or share it right away. You can edit again any time.',
      illustration: _Illustration.export,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.seenKey, true);
    if (mounted) context.go('/login');
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: Tokens.ivory,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                style: TextButton.styleFrom(
                  foregroundColor: Tokens.muted,
                  minimumSize: const Size(0, Tokens.minTouchTarget),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  textStyle: AppText.label.copyWith(fontSize: 15),
                ),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _GuidePageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? Tokens.clayButton : Tokens.borderStrong,
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: PrimaryButton(
                label: isLast ? 'Get started' : 'Next',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Illustration { upload, voice, edit, export }

class _GuidePage {
  const _GuidePage({
    required this.title,
    required this.body,
    required this.illustration,
  });

  final String title;
  final String body;
  final _Illustration illustration;
}

class _GuidePageView extends StatelessWidget {
  const _GuidePageView({required this.page});

  final _GuidePage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _illustration(),
          const SizedBox(height: 32),
          Text(page.title, style: AppText.display(30)),
          const SizedBox(height: 10),
          Text(page.body, style: AppText.bodyMuted),
        ],
      ),
    );
  }

  Widget _illustration() {
    return switch (page.illustration) {
      _Illustration.upload => _DashedCard(
          icon: Icons.file_upload_outlined,
          title: 'Choose video or audio',
          subtitle: 'MP4, MOV, MP3',
        ),
      _Illustration.voice => _DashedCard(
          icon: Icons.record_voice_over_outlined,
          title: 'Female, male, or auto',
          subtitle: 'Pick a voice or detect it',
        ),
      _Illustration.edit => _DashedCard(
          icon: Icons.tune_rounded,
          title: 'Text, logo, subtitles',
          subtitle: 'Plus blur and audio mix',
        ),
      _Illustration.export => Center(
          child: DubberCharacter(size: 250),
        ),
    };
  }
}

class _DashedCard extends StatelessWidget {
  const _DashedCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
        decoration: BoxDecoration(
          color: Tokens.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Tokens.clayButton),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.display(20),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: AppText.caption),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.uploadBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
