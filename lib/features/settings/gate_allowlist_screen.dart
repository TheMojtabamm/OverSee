import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../configs/gate_line_card.dart";

/// The allow-list lines for every gated lock this device created, ready to paste
/// into the server. Deleting a line on the server revokes that lock.
class GateAllowListScreen extends ConsumerWidget {
  const GateAllowListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(s.t("gate_allowlist"))),
      body: FutureBuilder<List<String>>(
        future: ref.read(identityStoreProvider).gateLines(),
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final lines = (snap.data ?? const <String>[]).reversed.toList();
          if (lines.isEmpty) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(s.t("gate_allowlist_empty"),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted)),
            ));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: lines.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => i == 0
                ? Text(s.t("gate_line_body"),
                    style: TextStyle(color: c.muted, height: 1.5))
                : GateLineCard(line: lines[i - 1]),
          );
        },
      ),
    );
  }
}
