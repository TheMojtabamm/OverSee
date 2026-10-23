import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../providers.dart";

/// The allow-list lines for every gated lock this device created, ready to paste
/// into the server's allow.txt. Deleting a line on the server revokes that lock.
class GateAllowListScreen extends ConsumerWidget {
  const GateAllowListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t("gate_allowlist"))),
      body: FutureBuilder<List<String>>(
        future: ref.read(identityStoreProvider).gateLines(),
        builder: (_, snap) {
          final lines = snap.data ?? const <String>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (lines.isEmpty)
            return Center(child: Text(s.t("gate_allowlist_empty")));
          final all = lines.join("\n");
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(s.t("gate_line_body")),
              const SizedBox(height: 12),
              SelectableText(all,
                  textDirection: TextDirection.ltr,
                  style:
                      const TextStyle(fontFamily: "monospace", fontSize: 12)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: all));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(s.t("copied"))));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(s.t("copy")),
              ),
            ],
          );
        },
      ),
    );
  }
}
