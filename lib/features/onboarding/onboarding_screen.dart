import "package:flutter/material.dart";

import "../../core/strings.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";

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
          const Positioned(
              top: 0, left: 0, right: 0, child: GlowBackdrop(height: 460)),
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
                            Container(
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    c.brand,
                                    Color.lerp(c.brand, Colors.blue, 0.45)!
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                      color: c.brand.withValues(alpha: 0.35),
                                      blurRadius: 48,
                                      spreadRadius: 2)
                                ],
                              ),
                              child: Icon(icon,
                                  size: 68, color: const Color(0xFF04201C)),
                            ),
                            const SizedBox(height: 40),
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
