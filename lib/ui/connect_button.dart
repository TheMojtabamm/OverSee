import "dart:math" as math;

import "package:flutter/material.dart";

import "theme.dart";

enum ConnectVisual { idle, connecting, connected, blocked, error }

/// The big round power button (Harbor): two quiet rings and a round core. Connecting: a spinning
/// arc. Connected: the core fills with the accent colour. Blocked: amber. Error: red.
class ConnectButton extends StatefulWidget {
  final ConnectVisual visual;
  final VoidCallback? onPressed;
  final double size;
  final String semanticsLabel;

  const ConnectButton({
    super.key,
    required this.visual,
    required this.onPressed,
    required this.semanticsLabel,
    this.size = 196,
  });

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ConnectButton old) {
    super.didUpdateWidget(old);
    if (old.visual != widget.visual) _sync();
  }

  void _sync() {
    // Don't run a ticker for the idle state (battery, and tests settle).
    if (widget.visual == ConnectVisual.idle) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.visual;
    final accent = switch (v) {
      ConnectVisual.idle => c.brand,
      ConnectVisual.connecting => c.brand,
      ConnectVisual.connected => c.brand,
      ConnectVisual.blocked => c.warn,
      ConnectVisual.error => c.bad,
    };
    final filled = v == ConnectVisual.connected;
    final size = widget.size;
    final surface = Theme.of(context).colorScheme.surface;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final enabled = widget.onPressed != null || v == ConnectVisual.connecting;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _RingPainter(
                  t: _c.value,
                  visual: v,
                  color: accent,
                  track: c.outline,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: size * 0.59,
                    height: size * 0.59,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? accent : surface,
                      boxShadow: [
                        BoxShadow(
                            color: (filled ? accent : Colors.black)
                                .withValues(alpha: filled ? 0.38 : 0.12),
                            blurRadius: filled ? 40 : 34,
                            offset: const Offset(0, 14))
                      ],
                    ),
                    child: Icon(
                      Icons.power_settings_new_rounded,
                      size: size * 0.22,
                      color: filled ? onAccent : accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double t;
  final ConnectVisual visual;
  final Color color;
  final Color track;

  _RingPainter(
      {required this.t,
      required this.visual,
      required this.color,
      required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r1 = size.width / 2 - 1;
    final r2 = r1 - size.width * 0.102;

    Paint ring(double w, Color col) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = col;

    final ringColor = switch (visual) {
      ConnectVisual.connected => color.withValues(alpha: 0.35),
      ConnectVisual.blocked => color,
      ConnectVisual.error => color.withValues(alpha: 0.5),
      _ => track,
    };
    canvas.drawCircle(center, r1, ring(1.5, ringColor));
    canvas.drawCircle(
        center, r2, ring(1.5, Color.lerp(track, color, 0.22) ?? track));

    if (visual == ConnectVisual.connecting) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: r1),
          t * 2 * math.pi,
          math.pi * 0.62,
          false,
          ring(3, color)..strokeCap = StrokeCap.round);
    } else if (visual == ConnectVisual.connected) {
      // One slow halo leaving the outer ring.
      final p = t % 1.0;
      canvas.drawCircle(center, r1 * (0.9 + 0.1 * p),
          ring(2, color.withValues(alpha: (1 - p) * 0.35)));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.visual != visual || old.color != color;
}
