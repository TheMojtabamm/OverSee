import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";

/// Checks the selected config the way the phone itself sees it: can the server be reached
/// (the app is excluded from its own VPN, so this is the real network path), what does a
/// WebSocket upgrade get back, and what did the core log. A locked config shows results
/// only — never its address, path or log lines.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _Line {
  final bool? ok; // null = info
  final String text;
  const _Line(this.ok, this.text);
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _lines = <_Line>[];
  final _log = <String>[];
  bool _running = false;

  void _add(bool? ok, String text) {
    if (mounted) setState(() => _lines.add(_Line(ok, text)));
  }

  Future<void> _run(VpnConfig c) async {
    setState(() {
      _running = true;
      _lines.clear();
      _log.clear();
    });
    final locked = c.locked;
    final host = c.host;
    final port = c.port;
    if (host == null || port == null) {
      _add(false, "This config has no server address.");
    } else {
      final where = locked ? "the server" : "$host:$port";
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(host, port,
            timeout: const Duration(seconds: 8));
        _add(true,
            "TCP connection to $where works (${sw.elapsedMilliseconds} ms)");
        if (!locked) await _wsProbe(c, s);
        s.destroy();
      } on Object catch (e) {
        _add(false,
            "Cannot reach $where from this phone: ${_short(e)}. Check the server's firewall/port and that the address is right.");
      }
    }
    if (!locked) await _readLog();
    if (mounted) setState(() => _running = false);
  }

  /// For `type=ws` links: send the HTTP upgrade the core would send and report the answer.
  Future<void> _wsProbe(VpnConfig c, Socket s) async {
    final u = Uri.tryParse(c.raw);
    final q = u?.queryParameters ?? const {};
    if ((q["type"] ?? "") != "ws") return;
    if ((q["security"] ?? "none") != "none") {
      _add(null, "WebSocket over TLS: only the TCP check is done here.");
      return;
    }
    final path = (q["path"] ?? "/").isEmpty ? "/" : q["path"]!;
    final hostHdr =
        (q["host"] ?? "").isNotEmpty ? q["host"]! : "${c.host}:${c.port}";
    final key = base64.encode(List<int>.generate(16, (i) => i * 7 + 3));
    s.write("GET $path HTTP/1.1\r\nHost: $hostHdr\r\nUpgrade: websocket\r\n"
        "Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n");
    try {
      final data = await s.first.timeout(const Duration(seconds: 8));
      final first = latin1.decode(data).split("\r\n").first;
      final code = int.tryParse(first.split(" ").elementAtOrNull(1) ?? "");
      if (code == 101) {
        _add(true, "Server accepted the WebSocket upgrade (101) on this path.");
      } else {
        _add(
            false,
            "Server answered \"$first\" to the WebSocket upgrade. "
            "400/404 = wrong path or Host; 401/403 = a gate/proxy in front wants a token "
            "(a plain link cannot pass it — use the locked .ovsea file); 5xx = the proxy "
            "in front cannot reach Xray.");
      }
    } on Object catch (e) {
      _add(false, "No answer to the WebSocket upgrade (${_short(e)}).");
    }
  }

  /// The core's own log lines for this process (an app can read only its own).
  Future<void> _readLog() async {
    try {
      final r = await Process.run("logcat", [
        "-d",
        "-t",
        "400",
        "-v",
        "time",
        "--pid=$pid",
        "-s",
        "GoLog",
      ]).timeout(const Duration(seconds: 5));
      final uuid = RegExp(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F-]{20,}");
      final lines = LineSplitter.split("${r.stdout}")
          .where((l) => l.contains("GoLog"))
          .map((l) => l.replaceAll(uuid, "<id>"))
          .toList();
      _log.addAll(lines.length > 40 ? lines.sublist(lines.length - 40) : lines);
      _add(
          null,
          _log.isEmpty
              ? "Core log: nothing recorded (connect first)."
              : "Core log: ${_log.length} lines below.");
    } on Object {
      _add(null, "Core log is not available on this device.");
    }
  }

  String _short(Object e) {
    final t = "$e".replaceAll(RegExp(r"\s+"), " ");
    return t.length > 120 ? "${t.substring(0, 120)}…" : t;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(selectedConfigProvider);
    final col = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text("Diagnostics")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (cfg == null)
            const EmptyState(
                icon: Icons.troubleshoot_rounded,
                title: "No config selected",
                body: "Pick a config on the home screen first.")
          else ...[
            Text(
                "Tests “${cfg.name.isEmpty ? "config" : cfg.name}” from this phone, outside the VPN. "
                "Connect first if you also want the core's log.",
                style: TextStyle(color: col.muted, height: 1.5)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _running ? null : () => _run(cfg),
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text("Run tests"),
            ),
            const SizedBox(height: 16),
            for (final l in _lines)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          l.ok == null
                              ? Icons.info_outline_rounded
                              : l.ok!
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                          size: 20,
                          color: l.ok == null
                              ? col.muted
                              : l.ok!
                                  ? col.good
                                  : col.bad),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(l.text,
                              style: const TextStyle(height: 1.4))),
                    ],
                  ),
                ),
              ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: SectionTitle("Core log")),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _log.join("\n")));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Log copied")));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text("Copy"),
                ),
              ]),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_log.join("\n"),
                      style: const TextStyle(
                          fontFamily: "monospace", fontSize: 11, height: 1.4)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
