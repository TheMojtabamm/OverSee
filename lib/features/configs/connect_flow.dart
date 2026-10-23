import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";

import "../../app.dart";
import "../../core/log.dart";
import "../../core/strings.dart";
import "../../data/ad_service.dart";
import "../../data/tunnel_service.dart";
import "../../domain/ad_content.dart";
import "../../domain/gate_token.dart";
import "../../domain/tunnel_settings.dart";
import "../../domain/vpn_config.dart";
import "../../domain/xray_config_builder.dart";
import "../../providers.dart";

/// Tap on a config: disconnect if it is the active one, otherwise connect.
///
/// Order matters for Google Play: the VPN disclosure + consent comes *before* the
/// system VPN permission prompt, and the ad comes *after* the tunnel is up.
Future<void> toggleConnection(
    BuildContext context, WidgetRef ref, VpnConfig c) async {
  final svc = ref.read(tunnelServiceProvider);
  final current = ref.read(tunnelStateProvider).valueOrNull ?? TunnelState.idle;
  final active = ref.read(activeConfigIdProvider);

  final busy = current.phase == TunnelPhase.connected ||
      current.phase == TunnelPhase.connecting ||
      current.phase == TunnelPhase.blocked;
  if (busy && active == c.id) {
    await svc.stop();
    return;
  }
  if (busy) {
    await svc.stop();
    // Let the previous service finish tearing down before starting a new one.
    await svc.states
        .firstWhere((s) => s.phase == TunnelPhase.disconnected)
        .timeout(const Duration(seconds: 5), onTimeout: () => TunnelState.idle);
  }
  if (!context.mounted) return;
  await _connect(context, ref, c);
}

Future<void> _connect(BuildContext context, WidgetRef ref, VpnConfig c) async {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final svc = ref.read(tunnelServiceProvider);
  final store = ref.read(settingsStoreProvider);

  if (c.isExpired()) {
    messenger.showSnackBar(SnackBar(content: Text(s.t("file_expired"))));
    return;
  }

  // 1. Third-party (owner) message, clearly labelled.
  if (c.locked) {
    final ok = await _showSponsored(context, ref, c);
    if (!ok || !context.mounted) return;
  }

  // 2. Prominent VPN disclosure, once, before the system permission prompt.
  if (!await store.disclosureAccepted()) {
    if (!context.mounted) return;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.vpn_lock, size: 40, color: accent),
        title: Text(s.t("disclosure_title")),
        content: SingleChildScrollView(child: Text(s.t("disclosure_body"))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t("cancel"))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t("agree"))),
        ],
      ),
    );
    if (agreed != true) return;
    await store.acceptDisclosure();
  }

  // 3. Notification permission (best effort) and the system VPN permission.
  await svc.requestNotifications();
  if (!await svc.prepare()) {
    messenger.showSnackBar(SnackBar(content: Text(s.t("vpn_denied"))));
    return;
  }

  // 4. Build the Xray config.
  final settings = await ref.read(settingsProvider.future);
  final String json;
  try {
    json = XrayConfigBuilder.build(c.raw, _optionsFor(c, settings));
  } on UnsupportedConfigException {
    messenger.showSnackBar(SnackBar(content: Text(s.t("unsupported"))));
    return;
  }

  // 5. Start and wait for the outcome.
  ref.read(activeConfigIdProvider.notifier).state = c.id;
  final outcome = Completer<TunnelState>();
  final sub = svc.states.listen((st) {
    if (!outcome.isCompleted &&
        (st.phase == TunnelPhase.connected || st.phase == TunnelPhase.error)) {
      outcome.complete(st);
    }
  });
  try {
    await svc.start(
      configJson: json,
      label: c.name.isNotEmpty
          ? c.name
          : (c.locked ? s.t("locked") : (c.host ?? "")),
      settings: settings,
    );
    final st = await outcome.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () => const TunnelState(TunnelPhase.error),
    );
    if (st.phase != TunnelPhase.connected) {
      await svc.stop();
      messenger.showSnackBar(SnackBar(content: Text(s.t("connect_failed"))));
      return;
    }
  } on PlatformException catch (e) {
    Log.d("start failed: ${e.code}");
    messenger.showSnackBar(SnackBar(content: Text(s.t("connect_failed"))));
    return;
  } finally {
    await sub.cancel();
  }

  // 6. Tunnel is up: this is the natural break for an ad.
  final first = !await store.firstConnectDone();
  await store.markFirstConnectDone();
  AdService.showAfterConnect(
    firstEverConnect: first,
    stillConnected: () =>
        ref.read(tunnelStateProvider).valueOrNull?.phase ==
        TunnelPhase.connected,
  );
}

/// Owner-supplied text/link from a locked file. Third-party content, so: labelled
/// "Sponsored", sanitised, https Telegram links only, and the choice is explicit.
Future<bool> _showSponsored(
    BuildContext context, WidgetRef ref, VpnConfig c) async {
  final s = S.of(context);
  final text = AdContent.text(c.adText);
  final url = AdContent.channelUrl(c.telegramUrl);
  if (text == null && url == null) return true;
  final trusted = await ref.read(trustedCreatorsProvider.future);
  if (!context.mounted) return false;

  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.campaign, size: 40, color: accent),
      title: Text(s.t("sponsored")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t("sponsored_note"),
              style: Theme.of(ctx).textTheme.bodySmall,
              textAlign: TextAlign.center),
          if (text != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(text, textAlign: TextAlign.center),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _CreatorLine(creator: c.creator, trusted: trusted),
          ),
          if (url != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(s.t("open_channel")),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t("cancel"))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t("continue"))),
      ],
    ),
  );
  return proceed == true;
}

class _CreatorLine extends ConsumerWidget {
  final String? creator;
  final Set<String> trusted;
  const _CreatorLine({required this.creator, required this.trusted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    final fp = creator;
    if (fp == null) {
      return Text(s.t("creator_unsigned"),
          style: style?.copyWith(color: Colors.orange),
          textAlign: TextAlign.center);
    }
    final isTrusted =
        ref.watch(trustedCreatorsProvider).valueOrNull?.contains(fp) ??
            trusted.contains(fp);
    return Column(
      children: [
        Text(
          "${isTrusted ? s.t("creator_verified") : s.t("creator_unknown")}\n$fp",
          style:
              style?.copyWith(color: isTrusted ? Colors.green : Colors.orange),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        ),
        TextButton(
          onPressed: () => ref
              .read(trustedCreatorsProvider.notifier)
              .setTrusted(fp, !isTrusted),
          child: Text(isTrusted ? s.t("untrust") : s.t("trust")),
        ),
      ],
    );
  }
}

TunnelOptions _optionsFor(VpnConfig c, TunnelSettings settings) {
  final o = settings.toOptions();
  if (!c.gated) return o;
  // The creator fingerprint is part of the token, so a gated file must carry a
  // *verified* signature; an unsigned or re-signed file cannot produce a token the
  // owner's server will accept.
  final fp = c.creator;
  if (!GateToken.available || fp == null) {
    throw const UnsupportedConfigException(
        "This gated config cannot be opened here");
  }
  return TunnelOptions(
    dohServers: o.dohServers,
    fragment: o.fragment,
    ipv6: o.ipv6,
    bypassLan: o.bypassLan,
    mtu: o.mtu,
    gateToken: GateToken.current(c.gateCode!, fp),
  );
}

/// Measure one config's latency through its own outbound (does not need the VPN on).
Future<void> testPing(WidgetRef ref, VpnConfig c) async {
  final ping = ref.read(pingProvider.notifier);
  ping.set(c.id, -2);
  try {
    final settings = await ref.read(settingsProvider.future);
    final json = XrayConfigBuilder.build(c.raw, _optionsFor(c, settings));
    ping.set(c.id, await ref.read(tunnelServiceProvider).testDelay(json));
  } on UnsupportedConfigException {
    ping.set(c.id, -1);
  }
}

/// Tests every config (a few at a time) and returns when done.
Future<void> testAllPings(WidgetRef ref, List<VpnConfig> configs) async {
  const parallel = 3;
  final queue = List<VpnConfig>.of(configs);
  await Future.wait(List.generate(parallel, (_) async {
    while (queue.isNotEmpty) {
      await testPing(ref, queue.removeLast());
    }
  }));
}
