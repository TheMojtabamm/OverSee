import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/app_config.dart";
import "../../core/strings.dart";
import "../../data/ad_service.dart";
import "../../domain/tunnel_settings.dart";
import "../../providers.dart";
import "app_picker_screen.dart";

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const TunnelSettings();
    final notifier = ref.read(settingsProvider.notifier);

    String splitLabel(SplitMode m) => switch (m) {
          SplitMode.all => s.t("split_all"),
          SplitMode.allow => s.t("split_allow"),
          SplitMode.deny => s.t("split_deny"),
        };

    return Scaffold(
      appBar: AppBar(title: Text(s.t("settings"))),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(s.t("kill_switch")),
            subtitle: Text(s.t("kill_switch_hint")),
            value: settings.killSwitch,
            onChanged: (v) => notifier.change((c) => c.copyWith(killSwitch: v)),
          ),
          ListTile(
            title: Text(s.t("system_vpn")),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => ref.read(tunnelServiceProvider).openVpnSettings(),
          ),
          const Divider(),
          ListTile(
            title: Text(s.t("dns")),
            subtitle: Text(s.t("dns_hint")),
            trailing: DropdownButton<DnsPreset>(
              value: settings.dns,
              onChanged: (v) {
                if (v != null) notifier.change((c) => c.copyWith(dns: v));
              },
              items: [
                for (final d in DnsPreset.values)
                  DropdownMenuItem(value: d, child: Text(d.name)),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(s.t("ipv6")),
            subtitle: Text(s.t("ipv6_hint")),
            value: settings.ipv6,
            onChanged: (v) => notifier.change((c) => c.copyWith(ipv6: v)),
          ),
          SwitchListTile(
            title: Text(s.t("fragment")),
            subtitle: Text(s.t("fragment_hint")),
            value: settings.fragment,
            onChanged: (v) => notifier.change((c) => c.copyWith(fragment: v)),
          ),
          SwitchListTile(
            title: Text(s.t("bypass_lan")),
            value: settings.bypassLan,
            onChanged: (v) => notifier.change((c) => c.copyWith(bypassLan: v)),
          ),
          const Divider(),
          ListTile(
            title: Text(s.t("split")),
            trailing: DropdownButton<SplitMode>(
              value: settings.splitMode,
              onChanged: (v) {
                if (v != null) notifier.change((c) => c.copyWith(splitMode: v));
              },
              items: [
                for (final m in SplitMode.values)
                  DropdownMenuItem(value: m, child: Text(splitLabel(m))),
              ],
            ),
          ),
          if (settings.splitMode != SplitMode.all)
            ListTile(
              title: Text(s.t("choose_apps")),
              subtitle: Text("${settings.apps.length}"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const AppPickerScreen()),
              ),
            ),
          const Divider(),
          FutureBuilder<String>(
            future: ref
                .read(identityStoreProvider)
                .load()
                .then((i) => i.fingerprint),
            builder: (_, snap) => ListTile(
              title: Text(s.t("your_creator_id")),
              subtitle:
                  Text("${snap.data ?? "…"}\n${s.t("your_creator_hint")}"),
              isThreeLine: true,
              trailing: const Icon(Icons.copy, size: 18),
              onTap: snap.data == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: snap.data!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(s.t("copied"))));
                    },
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(s.t("privacy_policy")),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final u = Uri.tryParse(AppConfig.privacyPolicyUrl);
              if (u == null || !u.hasScheme) {
                messenger
                    .showSnackBar(SnackBar(content: Text(s.t("no_policy"))));
                return;
              }
              await launchUrl(u, mode: LaunchMode.externalApplication);
            },
          ),
          FutureBuilder<bool>(
            future: AdService.privacyOptionsRequired(),
            builder: (_, snap) => snap.data == true
                ? ListTile(
                    title: Text(s.t("ad_privacy")),
                    onTap: AdService.showPrivacyOptions,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
