import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../app.dart";
import "../../core/strings.dart";
import "../../data/ad_service.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
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
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(configsProvider.notifier).reload(),
          ),
        ],
      ),
      body: configs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("$e")),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_lock, size: 64, color: Colors.grey),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        onTap: () => _connect(context, c),
      ),
    );
  }

  /// Tap a config: for a locked config that carries the owner's ad / channel,
  /// show it first; then connect. After a successful connect an ad is shown.
  Future<void> _connect(BuildContext context, VpnConfig c) async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final hasAd = c.adText != null && c.adText!.isNotEmpty;
    final hasTg = c.telegramUrl != null && c.telegramUrl!.isNotEmpty;

    if (c.locked && (hasAd || hasTg)) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.campaign, size: 48, color: accent),
          title: Text(c.name.isNotEmpty ? c.name : s.t("channel")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAd)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(c.adText!, textAlign: TextAlign.center),
                ),
              if (hasTg)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openUrl(c.telegramUrl!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(s.t("open_channel")),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t("cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t("continue")),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // TODO(engine): start the Xray tunnel here and continue only once it is up.
    // Until the engine is wired, this stands in for "connected" so the
    // post-connect ad flow can be exercised end-to-end.
    final connected = await _startTunnel(c);
    if (connected) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              "${s.t("connect_ok")} — ${c.name.isNotEmpty ? c.name : c.host ?? ""}")));
      AdService.showAfterConnect();
    }
  }

  Future<bool> _startTunnel(VpnConfig c) async => true;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
