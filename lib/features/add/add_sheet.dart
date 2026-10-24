import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "../editor/config_editor_screen.dart";
import "../subscriptions/subscriptions_screen.dart";
import "add_actions.dart";
import "qr_scan_screen.dart";

/// "Add" on the Home screen: every way to get a config into the app.
Future<void> showAddSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _AddSheet(host: context, ref: ref),
  );
}

class _AddSheet extends StatelessWidget {
  final BuildContext host;
  final WidgetRef ref;
  const _AddSheet({required this.host, required this.ref});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget opt(IconData icon, String title, String desc, VoidCallback run) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              run();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                IconTile(icon, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(desc,
                          style: TextStyle(
                              color: c.muted, fontSize: 12.5, height: 1.35)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Add a config",
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                "vless, vmess, trojan and shadowsocks links, or a locked .ovsea file.",
                style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 14),
            opt(
                Icons.content_paste_rounded,
                "Paste from clipboard",
                "One link, or several, one per line",
                () => importFromClipboard(host, ref)),
            opt(Icons.qr_code_scanner_rounded, "Scan a QR code",
                "Use the camera or a picture from your gallery", () async {
              final text = await Navigator.of(host).push<String>(
                  MaterialPageRoute(builder: (_) => const QrScanScreen()));
              if (text != null && host.mounted) {
                await importText(host, ref, text);
              }
            }),
            opt(
                Icons.insert_drive_file_outlined,
                "Open a file",
                ".ovsea file or a text file with links",
                () => importFromFile(host, ref)),
            opt(
                Icons.edit_note_rounded,
                "Type or paste a link",
                "A box for one or more links",
                () => importFromTypedText(host, ref)),
            opt(
                Icons.tune_rounded,
                "Create manually",
                "Fill in the server, transport and security yourself",
                () => Navigator.of(host).push(MaterialPageRoute<void>(
                    builder: (_) => const ConfigEditorScreen()))),
            opt(
                Icons.sync_rounded,
                "Add a subscription",
                "A link that gives you a list of configs",
                () => showAddSubscriptionDialog(host, ref)),
          ],
        ),
      ),
    );
  }
}
