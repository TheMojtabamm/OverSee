import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../data/tunnel_service.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../../ui/connect_button.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "../ads/banner_ad.dart";
import "../configs/connect_flow.dart";
import "../configs/share_sheet.dart";

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final configs = ref.watch(configsProvider);
    final list = configs.valueOrNull ?? const <VpnConfig>[];

    return Scaffold(
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: GlowBackdrop()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const _Header(),
                Expanded(
                  child: configs.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text("$e")),
                    data: (_) => list.isEmpty
                        ? EmptyState(
                            icon: Icons.vpn_key_rounded,
                            title: s.t("empty_title"),
                            body: s.t("empty_hint"),
                            actions: [
                              FilledButton.icon(
                                onPressed: () =>
                                    ref.read(tabProvider.notifier).state = 1,
                                icon: const Icon(Icons.add_rounded),
                                label: Text(s.t("empty_cta_add")),
                              ),
                            ],
                          )
                        : _Body(list: list),
                  ),
                ),
                const BannerAdBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(
                  colors: [c.brand, Color.lerp(c.brand, Colors.blue, 0.4)!]),
            ),
            child: const Icon(Icons.shield_rounded,
                size: 20, color: Color(0xFF04201C)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Oversea",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2)),
              Text(s.t("app_tagline"),
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final List<VpnConfig> list;
  const _Body({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final ping = ref.watch(pingProvider);
    final selected = ref.watch(selectedConfigProvider);

    // Fastest first; untested keep their order; failed go last.
    int rank(VpnConfig c) {
      final p = ping[c.id];
      if (p == null || p == -2) return 1 << 29;
      return p < 0 ? 1 << 30 : p;
    }

    final sorted = [...list]..sort((a, b) => rank(a).compareTo(rank(b)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _Hero(selected: selected),
        const SizedBox(height: 20),
        SectionTitle(
          "${s.t("your_configs")} · ${list.length}",
          trailing: TextButton.icon(
            onPressed: () => testAllPings(ref, list),
            icon: const Icon(Icons.speed_rounded, size: 18),
            label: Text(s.t("test_speed")),
          ),
        ),
        for (final c in sorted) ...[
          ConfigCard(config: c, selected: selected?.id == c.id),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Big button, status, timer and live speed.
class _Hero extends ConsumerWidget {
  final VpnConfig? selected;
  const _Hero({required this.selected});

  static String rate(int bytesPerSec) {
    if (bytesPerSec >= 1 << 20) {
      return "${(bytesPerSec / (1 << 20)).toStringAsFixed(1)} MB/s";
    }
    return "${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s";
  }

  static String total(int bytes) {
    if (bytes >= 1 << 30) {
      return "${(bytes / (1 << 30)).toStringAsFixed(2)} GB";
    }
    if (bytes >= 1 << 20) {
      return "${(bytes / (1 << 20)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / 1024).toStringAsFixed(0)} KB";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final st = ref.watch(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
    final active = ref.watch(activeConfigIdProvider);
    final since = ref.watch(connectedSinceProvider);

    final visual = switch (st.phase) {
      TunnelPhase.connected => ConnectVisual.connected,
      TunnelPhase.connecting => ConnectVisual.connecting,
      TunnelPhase.blocked => ConnectVisual.blocked,
      _ => ConnectVisual.idle,
    };
    final isConnected = st.phase == TunnelPhase.connected;
    final switching = isConnected &&
        selected != null &&
        active != null &&
        active != selected!.id;

    final (title, color) = switch (st.phase) {
      TunnelPhase.connected => (s.t("status_connected"), c.good),
      TunnelPhase.connecting => (s.t("status_connecting"), c.warn),
      TunnelPhase.blocked => (s.t("status_blocked"), c.bad),
      TunnelPhase.error => (s.t("status_error"), c.bad),
      TunnelPhase.disconnected => (s.t("status_disconnected"), c.muted),
    };

    final hint = switch (st.phase) {
      TunnelPhase.blocked => s.t("hero_blocked"),
      TunnelPhase.connected =>
        switching ? s.t("hero_switch_to") : s.t("hero_tap_disconnect"),
      TunnelPhase.connecting => "",
      _ => selected == null ? s.t("hero_add_first") : s.t("hero_tap_connect"),
    };

    return Column(
      children: [
        ConnectButton(
          visual: visual,
          semanticsLabel: hint.isEmpty ? title : "$title. $hint",
          onPressed: selected == null
              ? () => ref.read(tabProvider.notifier).state = 1
              : st.phase == TunnelPhase.connecting
                  ? null
                  : () {
                      if (st.phase == TunnelPhase.blocked ||
                          (isConnected && !switching)) {
                        ref.read(tunnelServiceProvider).stop();
                      } else {
                        toggleConnection(context, ref, selected!);
                      }
                    },
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(title,
              key: ValueKey(st.phase),
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(height: 4),
        if (isConnected && since != null)
          _Timer(since: since)
        else
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 14)),
        if (isConnected) ...[
          const SizedBox(height: 10),
          const _ExitIp(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _Stat(
                      icon: Icons.arrow_upward_rounded,
                      label: s.t("uploaded"),
                      rate: rate(st.upRate),
                      total: total(st.up))),
              const SizedBox(width: 10),
              Expanded(
                  child: _Stat(
                      icon: Icons.arrow_downward_rounded,
                      label: s.t("downloaded"),
                      rate: rate(st.downRate),
                      total: total(st.down))),
            ],
          ),
          if (switching) ...[
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ],
      ],
    );
  }
}

/// "Exit IP 203.0.113.7 · 🇩🇪 Germany", looked up through the tunnel.
class _ExitIp extends ConsumerWidget {
  const _ExitIp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final info = ref.watch(exitInfoProvider);
    final (icon, text) = info.when(
      loading: () => (Icons.public_rounded, s.t("exit_ip_checking")),
      error: (_, __) => (Icons.public_off_rounded, s.t("exit_ip_failed")),
      data: (v) => v == null
          ? (Icons.public_off_rounded, s.t("exit_ip_failed"))
          : (
              Icons.public_rounded,
              "${s.t("exit_ip")}  ${v.ip}${v.label.isEmpty ? "" : "  ·  ${v.label}"}"
            ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: c.muted, fontSize: 13)),
        ),
      ],
    );
  }
}

class _Timer extends StatefulWidget {
  final DateTime since;
  const _Timer({required this.since});
  @override
  State<_Timer> createState() => _TimerState();
}

class _TimerState extends State<_Timer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    String two(int n) => n.toString().padLeft(2, "0");
    final text =
        "${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}";
    return Text(text,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: context.colors.muted,
            fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String rate;
  final String total;
  const _Stat(
      {required this.icon,
      required this.label,
      required this.rate,
      required this.total});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconTile(icon, size: 36, color: c.brand),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rate,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Semantics(
                      label: label,
                      child: Text(total,
                          style: TextStyle(color: c.muted, fontSize: 12),
                          maxLines: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfigCard extends ConsumerWidget {
  final VpnConfig config;
  final bool selected;
  const ConfigCard({super.key, required this.config, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final cfg = config;
    final ms = ref.watch(pingProvider)[cfg.id];
    final st = ref.watch(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
    final isActive = ref.watch(activeConfigIdProvider) == cfg.id &&
        (st.phase == TunnelPhase.connected ||
            st.phase == TunnelPhase.connecting);
    final expired = cfg.isExpired();

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isActive ? c.good : (selected ? c.brand : c.outline),
          width: selected || isActive ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => ref.read(selectedConfigIdProvider.notifier).select(cfg.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              IconTile(cfg.locked ? Icons.lock_rounded : Icons.public_rounded,
                  color: expired ? c.bad : (isActive ? c.good : c.brand)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cfg.name.isNotEmpty ? cfg.name : (cfg.host ?? "—"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(cfg.protocol.label),
                        // Locked configs never reveal their server address.
                        if (cfg.locked)
                          Pill(s.t("locked"),
                              icon: Icons.lock_rounded, color: c.brand),
                        if (cfg.gated)
                          Pill("Gate",
                              icon: Icons.shield_moon_rounded, color: c.brand),
                        if (expired) Pill(s.t("expired"), color: c.bad),
                        if (!cfg.locked && cfg.host != null) Pill(cfg.host!),
                      ],
                    ),
                  ],
                ),
              ),
              if (ms != null)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: ms == -2
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          ms < 0 ? s.t("failed") : "$ms ${s.t("ms")}",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color:
                                ms < 0 ? c.bad : (ms < 400 ? c.good : c.warn),
                          ),
                        ),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: c.muted),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onSelected: (v) async {
                  switch (v) {
                    case "test":
                      testPing(ref, cfg);
                    case "share":
                      showShareSheet(context, cfg);
                    case "remove":
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(s.t("remove_title")),
                          content: Text(s.t("remove_body")),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(s.t("cancel"))),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(96, 44),
                                  backgroundColor: c.bad),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(s.t("remove")),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        ref.read(configsProvider.notifier).remove(cfg.id);
                      }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: "test",
                      child: _MenuRow(Icons.speed_rounded, s.t("test_speed"))),
                  // Locked configs cannot be re-shared: that would allow re-locking
                  // them under someone else's name.
                  if (!cfg.locked)
                    PopupMenuItem(
                        value: "share",
                        child: _MenuRow(Icons.ios_share_rounded, s.t("share"))),
                  PopupMenuItem(
                      value: "remove",
                      child: _MenuRow(
                          Icons.delete_outline_rounded, s.t("remove"),
                          color: c.bad)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _MenuRow(this.icon, this.text, {this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: color)),
        ],
      );
}
