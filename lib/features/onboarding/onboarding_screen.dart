import "package:flutter/material.dart";

import "../../core/strings.dart";
import "../../ui/theme.dart";

/// Three short pages shown once on first launch.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    final pages = [
      (Icons.power_settings_new_rounded, s.t("ob1_title"), s.t("ob1_body")),
      (Icons.lock_rounded, s.t("ob2_title"), s.t("ob2_body")),
      (Icons.gpp_good_rounded, s.t("ob3_title"), s.t("ob3_body")),
    ];
    final last = _i == pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: widget.onDone,
                      child: Text(s.t("ob_skip"),
                          style: TextStyle(color: c.muted))),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _i = i),
                    itemBuilder: (_, i) {
                      final (icon, title, body) = pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 270,
                              height: 215,
                              child: CustomPaint(
                                  painter: _ObArt(i,
                                      surface:
                                          Theme.of(context).colorScheme.surface,
                                      surface2: c.surfaceHigh,
                                      line: c.outline,
                                      accent: c.brand,
                                      onAccent: Theme.of(context)
                                          .colorScheme
                                          .onPrimary)),
                            ),
                            const SizedBox(height: 28),
                            Text(title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 14),
                            Text(body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: c.muted, height: 1.6, fontSize: 15)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _i ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _i ? c.brand : c.outline,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: FilledButton(
                    onPressed: last
                        ? widget.onDone
                        : () => _page.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic),
                    child: Text(last ? s.t("ob_start") : s.t("ob_next")),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three onboarding illustrations, drawn in the theme's colours (a 280 x 220 box).
class _ObArt extends CustomPainter {
  final int page;
  final Color surface, surface2, line, accent, onAccent;
  const _ObArt(this.page,
      {required this.surface,
      required this.surface2,
      required this.line,
      required this.accent,
      required this.onAccent});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 280, size.height / 220);
    Paint fill(Color c) => Paint()..color = c;
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    RRect rr(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

    canvas.drawCircle(const Offset(140, 110), 100, fill(surface2));
    switch (page) {
      case 0:
        for (final y in [52.0, 96.0, 140.0]) {
          canvas.drawRRect(rr(62, y, 156, 36, 12), fill(surface));
        }
        canvas.drawCircle(const Offset(82, 114), 7, fill(accent));
        canvas.drawCircle(const Offset(82, 70), 7, fill(surface2));
        canvas.drawCircle(const Offset(82, 158), 7, fill(surface2));
        canvas.drawRRect(rr(98, 108, 70, 6, 3), fill(surface2));
        canvas.drawRRect(rr(98, 64, 90, 6, 3), fill(surface2));
        canvas.drawRRect(rr(98, 152, 54, 6, 3), fill(surface2));
      case 1:
        canvas.drawCircle(const Offset(140, 110), 70, stroke(line, 2));
        final shackle = Path()
          ..moveTo(118, 100)
          ..lineTo(118, 84)
          ..arcToPoint(const Offset(162, 84),
              radius: const Radius.circular(22), clockwise: true)
          ..lineTo(162, 100);
        canvas.drawPath(shackle, stroke(accent, 10));
        canvas.drawRRect(rr(104, 100, 72, 62, 14), fill(accent));
        canvas.drawCircle(const Offset(140, 128), 7, fill(surface));
      default:
        for (final y in [130.0, 156.0]) {
          final w = Path()..moveTo(40, y);
          for (var i = 0; i < 3; i++) {
            final x = 40 + i * 70.0;
            w.quadraticBezierTo(x + 17.5, y - 28, x + 35, y);
            w.quadraticBezierTo(x + 52.5, y + 28, x + 70, y);
          }
          canvas.drawPath(w, stroke(line, 3));
        }
        final shield = Path()
          ..moveTo(140, 44)
          ..lineTo(180, 59)
          ..lineTo(180, 87)
          ..cubicTo(180, 113, 163, 127, 140, 133)
          ..cubicTo(117, 127, 100, 113, 100, 87)
          ..lineTo(100, 59)
          ..close();
        canvas.drawPath(shield, fill(accent));
        final tick = Path()
          ..moveTo(124, 88)
          ..lineTo(135, 99)
          ..lineTo(156, 77);
        canvas.drawPath(tick, stroke(onAccent, 5));
    }
  }

  @override
  bool shouldRepaint(_ObArt old) =>
      old.page != page || old.accent != accent || old.surface != surface;
}
