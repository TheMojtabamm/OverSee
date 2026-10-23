import "dart:math" as math;

import "package:flutter/material.dart";

import "theme.dart";

enum ConnectVisual { idle, connecting, connected, blocked }

/// The big round power button. Idle: calm ring. Connecting: spinning arc.
/// Connected: filled with a soft breathing halo. Blocked (kill switch): red.
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
    this.size = 176,
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
    final color = switch (v) {
      ConnectVisual.idle => c.muted,
      ConnectVisual.connecting => c.warn,
      ConnectVisual.connected => c.good,
      ConnectVisual.blocked => c.bad,
    };
    final filled = v == ConnectVisual.connected || v == ConnectVisual.blocked;
    final size = widget.size;

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: SizedBox(
          width: size + 40,
          height: size + 40,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _RingPainter(
                t: _c.value,
                visual: v,
                color: color,
                track: c.outline,
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  width: size * 0.74,
                  height: size * 0.74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: filled
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, Color.lerp(color, c.brand, 0.55)!],
                          )
                        : null,
                    color: filled ? null : c.surfaceHigh,
                    border: Border.all(
                        color: filled ? Colors.transparent : c.outline,
                        width: 1.5),
                    boxShadow: filled
                        ? [
                            BoxShadow(
                                color: color.withValues(alpha: 0.35),
                                blurRadius: 36,
                                spreadRadius: 2)
                          ]
                        : const [],
                  ),
                  child: Icon(
                    Icons.power_settings_new_rounded,
                    size: size * 0.34,
                    color: filled ? const Color(0xFF04201C) : color,
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
    final r = size.width / 2 - 6;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = track;
    canvas.drawCircle(center, r, base);

    switch (visual) {
      case ConnectVisual.connecting:
        final arc = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = color;
        canvas.drawArc(Rect.fromCircle(center: center, radius: r),
            t * 2 * math.pi, math.pi * 0.55, false, arc);
      case ConnectVisual.connected:
        // Two slow expanding halos, offset in phase.
        for (final phase in [0.0, 0.5]) {
          final p = (t + phase) % 1.0;
          canvas.drawCircle(
            center,
            r * (0.82 + 0.18 * p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = color.withValues(alpha: (1 - p) * 0.45),
          );
        }
        canvas.drawCircle(
            center,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = color.withValues(alpha: 0.7));
      case ConnectVisual.blocked:
        canvas.drawCircle(
            center,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = color.withValues(alpha: 0.8));
      case ConnectVisual.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.visual != visual || old.color != color;
}
