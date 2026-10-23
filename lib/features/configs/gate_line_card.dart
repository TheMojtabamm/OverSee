import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../core/strings.dart";
import "../../ui/theme.dart";

/// One gate allow-list line, with the two things the owner does with it: copy the line
/// (to paste into allow.txt / the `oversee` Locks tab) or copy the ready-made server command.
class GateLineCard extends StatefulWidget {
  final String line;
  const GateLineCard({super.key, required this.line});

  @override
  State<GateLineCard> createState() => _GateLineCardState();
}

class _GateLineCardState extends State<GateLineCard> {
  String? _done; // "line" | "cmd" while the confirmation is showing
  Timer? _t;

  String get _command => 'sudo oversee add "${widget.line}"';

  void _copy(String what, String text) {
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _done = what);
    _t?.cancel();
    _t = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _done = null);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    Widget btn(String what, String label, IconData icon, String text,
        {required bool primary}) {
      final done = _done == what;
      final icn = Icon(done ? Icons.check_rounded : icon, size: 18);
      final lbl = Text(done ? s.t("copied_short") : label);
      return primary
          ? FilledButton.icon(
              onPressed: () => _copy(what, text), icon: icn, label: lbl)
          : OutlinedButton.icon(
              onPressed: () => _copy(what, text), icon: icn, label: lbl);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.brand.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(widget.line,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  fontFamily: "monospace", fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 12),
          btn("line", s.t("copy_line"), Icons.copy_rounded, widget.line,
              primary: true),
          const SizedBox(height: 8),
          btn("cmd", s.t("copy_cmd"), Icons.terminal_rounded, _command,
              primary: false),
        ],
      ),
    );
  }
}

/// Shown once, right after locking: the creator must put this line on the server
/// before anyone can connect. (It stays retrievable under Settings → Gate allow-list.)
Future<void> showGateLineDialog(BuildContext context, String line) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final s = S.of(ctx);
        final c = ctx.colors;
        Widget step(int n, String text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: c.brand.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Text("$n",
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c.brand)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(text,
                          style: const TextStyle(height: 1.4, fontSize: 14))),
                ],
              ),
            );
        return AlertDialog(
          icon: Icon(Icons.vpn_key_rounded, size: 36, color: c.brand),
          title: Text(s.t("gate_line_title"), textAlign: TextAlign.center),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                step(1, s.t("gate_step1")),
                GateLineCard(line: line),
                const SizedBox(height: 14),
                step(2, s.t("gate_step2")),
                step(3, s.t("gate_step3")),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.t("share_file"))),
          ],
        );
      },
    );
