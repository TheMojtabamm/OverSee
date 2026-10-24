import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../data/tunnel_service.dart";
import "../../domain/vpn_config.dart";
import "../../domain/xray_config_builder.dart";
import "../../providers.dart";
import "../../ui/connect_button.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "../add/add_sheet.dart";
import "../ads/banner_ad.dart";
import "../configs/config_actions.dart";
import "../configs/connect_flow.dart";

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(configsProvider);
    final list = configs.valueOrNull ?? const <VpnConfig>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _Header(),
            Expanded(
              child: configs.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text("$e")),
                data: (_) => _Body(list: list),
              ),
            ),
            const BannerAdBox(),
          ],
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final phase =
        ref.watch(tunnelStateProvider.select((v) => v.valueOrNull?.phase));
    final info = phase == TunnelPhase.connected
        ? ref.watch(exitInfoProvider).valueOrNull
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
            child: Icon(Icons.waves_rounded,
                size: 17, color: Theme.of(context).colorScheme.onPrimary),
          ),
          const SizedBox(width: 8),
          const Text("Oversea",
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: info != null
                          ? c.brand.withValues(alpha: .4)
                          : c.outline),
                ),
                child: Text(
                  info != null ? info.ip : s.t("not_protected"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: info != null ? c.brand : c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
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
    final c = context.colors;
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
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        _Hero(selected: selected),
        _Notice(selected: selected),
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: s.t("configs_header"),
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                  if (list.isNotEmpty)
                    TextSpan(
                        text: "  ${list.length}",
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: c.muted)),
                ])),
              ),
              if (list.isNotEmpty)
                _LinkButton(
                  icon: Icons.bolt_rounded,
                  label: s.t("test_speed"),
                  onTap: () => testAllPings(ref, list),
                ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () => showAddSheet(context, ref),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                        fontFamily: AppTheme.font,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.t("add_short")),
              ),
            ],
          ),
        ),
        if (list.isEmpty)
          _Empty(onAdd: () => showAddSheet(context, ref))
        else
          for (final cfg in sorted) ...[
            ConfigCard(config: cfg, selected: selected?.id == cfg.id),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: c.brand),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: c.brand)),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 26, 10, 10),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration:
                BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
            child: Icon(Icons.add_link_rounded, size: 38, color: c.brand),
          ),
          const SizedBox(height: 16),
          Text(s.t("empty_title"),
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(s.t("empty_hint"),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.5, fontSize: 14)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(s.t("empty_cta_add")),
          ),
        ],
      ),
    );
  }
}

/// Big orb, status, timer.
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
      TunnelPhase.error => ConnectVisual.error,
      _ => ConnectVisual.idle,
    };
    final isConnected = st.phase == TunnelPhase.connected;
    final switching = isConnected &&
        selected != null &&
        active != null &&
        active != selected!.id;

    final title = switch (st.phase) {
      TunnelPhase.connected => s.t("status_connected"),
      TunnelPhase.connecting => s.t("status_connecting"),
      TunnelPhase.blocked => s.t("status_blocked"),
      TunnelPhase.error => s.t("status_error"),
      TunnelPhase.disconnected => s.t("status_disconnected"),
    };

    final hint = switch (st.phase) {
      TunnelPhase.blocked => s.t("hero_blocked"),
      TunnelPhase.connected =>
        switching ? s.t("hero_switch_to") : s.t("hero_tap_disconnect"),
      TunnelPhase.connecting => "",
      _ => selected == null ? s.t("hero_add_first") : s.t("hero_tap_connect"),
    };

    final expired = selected?.isExpired() ?? false;
    final canTap = selected != null &&
        st.phase != TunnelPhase.connecting &&
        !(expired && !isConnected);

    return Column(
      children: [
        const SizedBox(height: 18),
        ConnectButton(
          visual: visual,
          semanticsLabel: hint.isEmpty ? title : "$title. $hint",
          onPressed: selected == null
              ? null
              : !canTap
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
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(title,
              key: ValueKey(st.phase),
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.3)),
        ),
        const SizedBox(height: 4),
        if (isConnected && since != null)
          _Timer(since: since)
        else
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 14)),
        if (isConnected) ...[
          const SizedBox(height: 8),
          const _ExitIp(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _Stat(
                      icon: Icons.arrow_downward_rounded,
                      label: s.t("downloaded"),
                      rate: rate(st.downRate),
                      total: total(st.down))),
              const SizedBox(width: 10),
              Expanded(
                  child: _Stat(
                      icon: Icons.arrow_upward_rounded,
                      label: s.t("uploaded"),
                      rate: rate(st.upRate),
                      total: total(st.up))),
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

/// Status cards under the orb: blocked, error, expired, not encrypted.
class _Notice extends ConsumerWidget {
  final VpnConfig? selected;
  const _Notice({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final st = ref.watch(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
    final svc = ref.read(tunnelServiceProvider);
    final cfg = selected;

    if (st.phase == TunnelPhase.blocked) {
      return _NoticeCard(
        color: c.warn,
        icon: Icons.info_outline_rounded,
        title: s.t("notice_blocked_t"),
        body: s.t("notice_blocked_d"),
        actions: [
          FilledButton(
              onPressed: cfg == null
                  ? null
                  : () => toggleConnection(context, ref, cfg),
              style: _small,
              child: Text(s.t("reconnect"))),
          OutlinedButton(
              onPressed: svc.stop,
              style: _smallOutline(c),
              child: Text(s.t("disconnect"))),
        ],
      );
    }
    if (st.phase == TunnelPhase.error) {
      return _NoticeCard(
        color: c.bad,
        icon: Icons.warning_amber_rounded,
        title: s.t("notice_error_t"),
        body: (st.message ?? "").isEmpty ? s.t("connect_failed") : st.message!,
        actions: [
          FilledButton(
              onPressed: cfg == null
                  ? null
                  : () => toggleConnection(context, ref, cfg),
              style: _small,
              child: Text(s.t("try_again"))),
        ],
      );
    }
    if (cfg != null &&
        cfg.isExpired() &&
        st.phase == TunnelPhase.disconnected) {
      return _NoticeCard(
        color: c.bad,
        icon: Icons.warning_amber_rounded,
        title: s.t("notice_expired_t"),
        body: s.t("file_expired"),
      );
    }
    if (cfg != null && XrayConfigBuilder.isUnencrypted(cfg.raw)) {
      return _NoticeCard(
        color: c.warn,
        icon: Icons.lock_open_rounded,
        title: s.t("notice_noenc_t"),
        body: s.t("notice_noenc_d"),
      );
    }
    return const SizedBox.shrink();
  }

  static final ButtonStyle _small = FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: const TextStyle(
          fontFamily: AppTheme.font,
          fontSize: 13,
          fontWeight: FontWeight.w600));

  static ButtonStyle _smallOutline(AppColors c) => OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: BorderSide(color: c.outline),
      textStyle: const TextStyle(
          fontFamily: AppTheme.font,
          fontSize: 13,
          fontWeight: FontWeight.w600));
}

class _NoticeCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  const _NoticeCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: .10), surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(body,
                    style:
                        TextStyle(color: c.muted, fontSize: 13, height: 1.45)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
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
            fontSize: 14,
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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: c.muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
            const SizedBox(height: 6),
            Text(rate,
                maxLines: 1,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text(total,
                maxLines: 1, style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// One config row: tile, name, badges, ping, menu.
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
    final trusted = ref.watch(trustedCreatorsProvider).valueOrNull ?? const {};
    final isActive = ref.watch(activeConfigIdProvider) == cfg.id &&
        (st.phase == TunnelPhase.connected ||
            st.phase == TunnelPhase.connecting);
    final expired = cfg.isExpired();
    final subtitle = cfg.locked
        ? "${cfg.protocol.label}  ·  ${cfg.creator == null ? "—" : "by ${cfg.creator!}"}"
        : "${cfg.protocol.label}  ·  ${cfg.host ?? "—"}${cfg.port == null ? "" : ":${cfg.port}"}";

    return Opacity(
      opacity: expired ? .75 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isActive ? c.good : (selected ? c.brand : c.outline),
            width: selected || isActive ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: () =>
              ref.read(selectedConfigIdProvider.notifier).select(cfg.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                IconTile(cfg.locked ? Icons.lock_rounded : Icons.dns_rounded,
                    size: 42,
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
                              fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(color: c.muted, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (cfg.locked)
                            Pill(s.t("locked"),
                                icon: Icons.lock_rounded, color: c.brand),
                          if (cfg.gated)
                            Pill("Gate",
                                icon: Icons.shield_moon_rounded,
                                color: c.brand),
                          if (XrayConfigBuilder.isUnencrypted(cfg.raw))
                            Pill(s.t("no_tls"),
                                icon: Icons.lock_open_rounded, color: c.warn),
                          if (expired) Pill(s.t("expired"), color: c.bad),
                          if (cfg.locked && cfg.creator != null)
                            trusted.contains(cfg.creator)
                                ? Pill(s.t("badge_verified"), color: c.good)
                                : Pill(s.t("badge_unverified"), color: c.warn),
                          if (cfg.locked && cfg.creator == null)
                            Pill(s.t("badge_unsigned"), color: c.bad),
                          if (cfg.source.startsWith("Subscription"))
                            Pill(cfg.source.replaceFirst("Subscription: ", ""),
                                icon: Icons.sync_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
                _PingLabel(ms: ms, onTap: () => testPing(ref, cfg)),
                IconButton(
                  icon: Icon(Icons.more_horiz_rounded, color: c.muted),
                  tooltip: "More",
                  onPressed: () => showConfigActions(context, ref, cfg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PingLabel extends StatelessWidget {
  final int? ms;
  final VoidCallback onTap;
  const _PingLabel({required this.ms, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;
    if (ms == null) return const SizedBox(width: 4);
    if (ms == -2) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final v = ms!;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          v < 0 ? s.t("failed") : "$v ${s.t("ms")}",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
            color: v < 0 ? c.bad : (v < 400 ? c.good : c.warn),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
