import "dart:convert";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/log.dart";
import "../../core/strings.dart";
import "../../providers.dart";
import "importer.dart";

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

  /// Add whatever is in the box: plain Xray config lines, or a pasted locked blob.
  Future<void> _addText() async {
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;
    await _import(text);
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      await _import(utf8.decode(bytes));
    } catch (e) {
      Log.d("pick failed: $e");
      if (mounted) _say(S.of(context).t("import_invalid"), ok: false);
    }
  }

  Future<void> _import(String text) async {
    try {
      final out = await Importer.fromText(text);
      if (!mounted) return;
      if (!out.isOk) {
        _say(S.of(context).t(out.errorKey!), ok: false);
        return;
      }
      await ref.read(configsProvider.notifier).addAll(out.configs);
      _say(
          "+${out.configs.length}${out.skipped > 0 ? " (−${out.skipped})" : ""}",
          ok: true);
      await _done();
    } catch (e) {
      Log.d("import failed: $e");
      if (mounted) _say(S.of(context).t("import_invalid"), ok: false);
    }
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
