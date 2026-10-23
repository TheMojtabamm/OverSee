import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../app.dart";
import "../../core/strings.dart";
import "../../data/tunnel_service.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../settings/settings_screen.dart";
import "connect_flow.dart";
import "share_sheet.dart";

class ConfigsScreen extends ConsumerWidget {
  const ConfigsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final configs = ref.watch(configsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
            "${s.t("configs_title")} (${configs.valueOrNull?.length ?? 0})"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: s.t("settings"),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _StatusCard(),
          Expanded(
            child: configs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("$e")),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.vpn_lock,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            Text(s.t("empty_title"),
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 8),
                            Text(s.t("empty_hint"),
                                style: const TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => _ConfigTile(config: list[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard();

  static String _rate(int bytesPerSec) {
    if (bytesPerSec >= 1 << 20) {
      return "${(bytesPerSec / (1 << 20)).toStringAsFixed(1)} MB/s";
    }
    return "${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final st = ref.watch(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
    if (st.phase == TunnelPhase.disconnected) return const SizedBox.shrink();

    final (label, color) = switch (st.phase) {
      TunnelPhase.connecting => (s.t("status_connecting"), Colors.amber),
      TunnelPhase.connected => (s.t("status_connected"), Colors.green),
      TunnelPhase.blocked => (s.t("status_blocked"), Colors.red),
      TunnelPhase.error => (s.t("status_error"), Colors.red),
      TunnelPhase.disconnected => ("", Colors.grey),
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.circle, size: 12, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  if (st.phase == TunnelPhase.connected)
                    Text("↑ ${_rate(st.upRate)}   ↓ ${_rate(st.downRate)}",
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (st.phase != TunnelPhase.error)
              FilledButton.tonal(
                onPressed: () => ref.read(tunnelServiceProvider).stop(),
                child: Text(s.t("disconnect")),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConfigTile extends ConsumerWidget {
  final VpnConfig config;
  const _ConfigTile({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = config;
    final st = ref.watch(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
    final isActive = ref.watch(activeConfigIdProvider) == c.id &&
        (st.phase == TunnelPhase.connected ||
            st.phase == TunnelPhase.connecting);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: isActive
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: accent, width: 1.5),
            )
          : null,
      child: ListTile(
        leading: Icon(c.locked ? Icons.lock : Icons.shield, color: accent),
        title: Text(c.name.isNotEmpty ? c.name : (c.host ?? "?")),
        // Locked configs never reveal their server address.
        subtitle: Text(c.locked
            ? "${c.protocol.label} • ${s.t("locked")}"
            : "${c.protocol.label} • ${c.host ?? "?"}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Locked configs cannot be re-shared: that would allow re-locking
            // them under someone else's name.
            if (!c.locked)
              IconButton(
                icon: const Icon(Icons.share, size: 20),
                onPressed: () => showShareSheet(context, c),
              ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
              onPressed: () => ref.read(configsProvider.notifier).remove(c.id),
            ),
          ],
        ),
        onTap: () => toggleConnection(context, ref, c),
      ),
    );
  }
}
