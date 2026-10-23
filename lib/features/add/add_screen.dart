import "dart:convert";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/log.dart";
import "../../core/strings.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
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

  Future<void> _import(String text) async {
    try {
      final out = await Importer.fromText(text);
      if (!mounted) return;
      if (!out.isOk) {
        _say(S.of(context).t(out.errorKey!), ok: false);
        return;
      }
      await ref.read(configsProvider.notifier).addAll(out.configs);
      if (!mounted) return;
      _ctrl.clear();
      final n = out.configs.length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "${S.of(context).t("imported")}: $n${out.skipped > 0 ? " (${out.skipped} skipped)" : ""}")));
      setState(() => _result = null);
      ref.read(tabProvider.notifier).state = 0;
    } catch (e) {
      Log.d("import failed: $e");
      if (mounted) _say(S.of(context).t("import_invalid"), ok: false);
    }
  }

  /// One tap: read the clipboard and import it.
  Future<void> _fromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final t = data?.text ?? "";
    if (t.trim().isEmpty) {
      _say(S.of(context).t("clipboard_empty"), ok: false);
      return;
    }
    await _import(t);
  }

  Future<void> _fromFile() async {
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned(
              top: 0, left: 0, right: 0, child: GlowBackdrop(height: 260)),
          SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(s.t("add_title"),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(s.t("add_subtitle"),
                    style: TextStyle(color: c.muted, height: 1.5)),
                const SizedBox(height: 20),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.content_paste_go_rounded,
                          title: s.t("add_from_clipboard"),
                          onTap: _fromClipboard,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.lock_open_rounded,
                          title: s.t("add_from_file"),
                          onTap: _fromFile,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SectionTitle(s.t("add_manual")),
                TextField(
                  controller: _ctrl,
                  minLines: 5,
                  maxLines: 8,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: "monospace", fontSize: 13),
                  decoration: InputDecoration(hintText: s.t("add_hint")),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final p in const [
                      "VLESS",
                      "VMess",
                      "Trojan",
                      "Shadowsocks"
                    ])
                      Pill(p)
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    if (_ctrl.text.trim().isNotEmpty) _import(_ctrl.text);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(s.t("add_btn")),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (_ok ? c.good : c.bad).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            _ok
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            color: _ok ? c.good : c.bad),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_result!,
                                style: TextStyle(
                                    color: _ok ? c.good : c.bad, height: 1.4))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon, size: 46),
                const SizedBox(height: 14),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        height: 1.3)),
              ],
            ),
          ),
        ),
      );
}
