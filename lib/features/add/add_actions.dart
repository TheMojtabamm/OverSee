import "dart:convert";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/log.dart";
import "../../core/strings.dart";
import "../../providers.dart";
import "importer.dart";

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Imports pasted / scanned / opened text and reports the result in a snack bar.
/// Returns true when at least one config was added.
Future<bool> importText(
    BuildContext context, WidgetRef ref, String text) async {
  final s = S.of(context);
  try {
    final out = await Importer.fromText(text);
    if (!context.mounted) return false;
    if (!out.isOk) {
      _snack(context, s.t(out.errorKey!));
      return false;
    }
    await ref.read(configsProvider.notifier).addAll(out.configs);
    if (!context.mounted) return true;
    final n = out.configs.length;
    _snack(context,
        "${s.t("imported")}: $n${out.skipped > 0 ? " (${out.skipped} skipped)" : ""}");
    return true;
  } catch (e) {
    Log.d("import failed: $e");
    if (context.mounted) _snack(context, s.t("import_invalid"));
    return false;
  }
}

Future<void> importFromClipboard(BuildContext context, WidgetRef ref) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return;
  final t = data?.text ?? "";
  if (t.trim().isEmpty) {
    _snack(context, S.of(context).t("clipboard_empty"));
    return;
  }
  await importText(context, ref, t);
}

Future<void> importFromFile(BuildContext context, WidgetRef ref) async {
  try {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null || !context.mounted) return;
    await importText(context, ref, utf8.decode(bytes, allowMalformed: true));
  } catch (e) {
    Log.d("pick failed: $e");
    if (context.mounted) _snack(context, S.of(context).t("import_invalid"));
  }
}

/// A small dialog with a multi-line box: type or paste a link, or several.
Future<void> importFromTypedText(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Paste a link"),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontFamily: "monospace", fontSize: 13),
        decoration: InputDecoration(hintText: S.of(ctx).t("add_hint")),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).t("cancel"))),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(S.of(ctx).t("add_short"))),
      ],
    ),
  );
  ctrl.dispose();
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importText(context, ref, text);
}
