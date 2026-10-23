import "dart:convert";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/log.dart";
import "../../core/strings.dart";
import "../../domain/ad_content.dart";
import "../../domain/config_parser.dart";
import "../../domain/locked_config_codec.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";

class AddScreen extends ConsumerStatefulWidget {
  const AddScreen({super.key});
  @override
  ConsumerState<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends ConsumerState<AddScreen> {
  final _ctrl = TextEditingController();
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _say(String m, {required bool ok}) => setState(() {
        _result = m;
        _ok = ok;
      });

  Future<void> _done() async {
    _ctrl.clear();
    ref.read(tabProvider.notifier).state = 0;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text ?? "";
    if (!mounted) return;
    if (t.isEmpty) {
      _say(S.of(context).t("clipboard_empty"), ok: false);
      return;
    }
    _ctrl.text = t;
  }

  /// Add whatever is in the box: plain Xray config lines, or a pasted blob.
  Future<void> _addText() async {
    final s = S.of(context);
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      if (LockedConfigCodec.looksLocked(text)) {
        await _importLocked(text);
        return;
      }
      final all = ConfigParser.parseMany(text);
      final xray = all.where((c) => c.protocol.isXray).toList();
      if (xray.isEmpty) {
        _say(s.t("no_xray"), ok: false);
        return;
      }
      await ref.read(configsProvider.notifier).addAll(xray);
      final skipped = all.length - xray.length;
      _say("+${xray.length}${skipped > 0 ? " (−$skipped)" : ""}", ok: true);
      await _done();
    } catch (e) {
      Log.d("add failed: $e");
      _say("Error", ok: false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      await _importLocked(utf8.decode(bytes));
    } catch (e) {
      Log.d("pick failed: $e");
      _say("Could not read file", ok: false);
    }
  }

  Future<void> _importLocked(String blob) async {
    final s = S.of(context);
    if (!LockedConfigCodec.hasKey) {
      _say(s.t("no_key"), ok: false);
      return;
    }
    final ConfigEnvelope env;
    try {
      env = await LockedConfigCodec.decodeConfig(blob);
    } catch (_) {
      // Deliberately uninformative: don't tell an attacker which check failed.
      _say("Invalid or unsupported file", ok: false);
      return;
    }
    if (env.isExpired()) {
      _say(s.t("file_expired"), ok: false);
      return;
    }
    final parsed = ConfigParser.parseMany(env.config)
        .where((c) => c.protocol.isXray)
        .toList();
    if (parsed.isEmpty) {
      _say(s.t("no_xray"), ok: false);
      return;
    }
    // Locked configs keep their server hidden and cannot be copied or re-shared.
    final stored = parsed
        .map((c) => VpnConfig(
              id: c.id,
              name: c.name,
              protocol: c.protocol,
              raw: c.raw,
              source: "locked",
              adText: AdContent.text(env.adText),
              telegramUrl: AdContent.channelUrl(env.telegramUrl),
              locked: true,
              creator: env.creator,
              gateCode: env.gateCode,
              expiresAt: env.expiresAt,
            ))
        .toList();
    await ref.read(configsProvider.notifier).addAll(stored);
    _say("+${stored.length}", ok: true);
    await _done();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t("add_title"))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              maxLines: 6,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: s.t("add_hint"),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: Text(s.t("paste")),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addText,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.t("add")),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.lock_open, size: 18),
              label: Text(s.t("import_locked")),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_ok ? Colors.green : Colors.red).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _ok ? Colors.green : Colors.red),
                ),
                child: Text(_result!,
                    style: TextStyle(color: _ok ? Colors.green : Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
