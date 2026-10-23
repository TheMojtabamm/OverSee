import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:url_launcher/url_launcher.dart";

import "../../core/app_config.dart";
import "../../core/strings.dart";
import "../../data/ad_service.dart";
import "../../domain/tunnel_settings.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "app_picker_screen.dart";
import "gate_allowlist_screen.dart";

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final c = context.colors;
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const TunnelSettings();
    final notifier = ref.read(settingsProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);

    String splitLabel(SplitMode m) => switch (m) {
          SplitMode.all => s.t("split_all"),
          SplitMode.allow => s.t("split_allow"),
          SplitMode.deny => s.t("split_deny"),
        };
    String themeLabel(ThemeMode m) => switch (m) {
          ThemeMode.system => s.t("theme_system"),
          ThemeMode.light => s.t("theme_light"),
          ThemeMode.dark => s.t("theme_dark"),
        };
    String dnsLabel(DnsPreset d) => switch (d) {
          DnsPreset.tunnel => "Plain (via tunnel)",
          DnsPreset.cloudflare => "Cloudflare DoH",
          DnsPreset.google => "Google DoH",
          DnsPreset.quad9 => "Quad9 DoH",
        };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: Text(s.t("settings"),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SectionTitle(s.t("g_connection")),
            SettingsGroup(children: [
              SettingsRow(
                icon: Icons.gpp_good_rounded,
                title: s.t("kill_switch"),
                subtitle: s.t("kill_switch_hint"),
                trailing: Switch(
                    value: settings.killSwitch,
                    onChanged: (v) =>
                        notifier.change((x) => x.copyWith(killSwitch: v))),
                onTap: () => notifier.change(
                    (x) => x.copyWith(killSwitch: !settings.killSwitch)),
              ),
              SettingsRow(
                icon: Icons.settings_applications_rounded,
                title: s.t("system_vpn"),
                subtitle: s.t("system_vpn_hint"),
                trailing:
                    Icon(Icons.open_in_new_rounded, size: 18, color: c.muted),
                onTap: () => ref.read(tunnelServiceProvider).openVpnSettings(),
              ),
              SettingsRow(
                icon: Icons.language_rounded,
                title: s.t("ipv6"),
                subtitle: s.t("ipv6_hint"),
                trailing: Switch(
                    value: settings.ipv6,
                    onChanged: (v) =>
                        notifier.change((x) => x.copyWith(ipv6: v))),
                onTap: () =>
                    notifier.change((x) => x.copyWith(ipv6: !settings.ipv6)),
              ),
              SettingsRow(
                icon: Icons.auto_fix_high_rounded,
                title: s.t("fragment"),
                subtitle: s.t("fragment_hint"),
                trailing: Switch(
                    value: settings.fragment,
                    onChanged: (v) =>
                        notifier.change((x) => x.copyWith(fragment: v))),
                onTap: () => notifier
                    .change((x) => x.copyWith(fragment: !settings.fragment)),
              ),
            ]),
            const SizedBox(height: 20),
            SectionTitle(s.t("g_routing")),
            SettingsGroup(children: [
              SettingsRow(
                icon: Icons.dns_rounded,
                title: s.t("dns"),
                subtitle: s.t("dns_hint"),
                trailing: _Choice<DnsPreset>(
                  value: settings.dns,
                  values: DnsPreset.values,
                  label: dnsLabel,
                  onChanged: (v) => notifier.change((x) => x.copyWith(dns: v)),
                ),
              ),
              SettingsRow(
                icon: Icons.lan_rounded,
                title: s.t("bypass_lan"),
                trailing: Switch(
                    value: settings.bypassLan,
                    onChanged: (v) =>
                        notifier.change((x) => x.copyWith(bypassLan: v))),
                onTap: () => notifier
                    .change((x) => x.copyWith(bypassLan: !settings.bypassLan)),
              ),
              SettingsRow(
                icon: Icons.apps_rounded,
                title: s.t("split"),
                trailing: _Choice<SplitMode>(
                  value: settings.splitMode,
                  values: SplitMode.values,
                  label: splitLabel,
                  onChanged: (v) =>
                      notifier.change((x) => x.copyWith(splitMode: v)),
                ),
              ),
              if (settings.splitMode != SplitMode.all)
                SettingsRow(
                  icon: Icons.checklist_rounded,
                  title: s.t("choose_apps"),
                  subtitle: "${settings.apps.length}",
                  trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const AppPickerScreen())),
                ),
            ]),
            const SizedBox(height: 20),
            SectionTitle(s.t("g_creator")),
            SettingsGroup(children: [
              FutureBuilder<String>(
                future: ref
                    .read(identityStoreProvider)
                    .load()
                    .then((i) => i.fingerprint),
                builder: (_, snap) => SettingsRow(
                  icon: Icons.fingerprint_rounded,
                  title: s.t("your_creator_id"),
                  subtitle: "${snap.data ?? "…"}\n${s.t("your_creator_hint")}",
                  trailing: Icon(Icons.copy_rounded, size: 18, color: c.muted),
                  onTap: snap.data == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: snap.data!));
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.t("copied"))));
                        },
                ),
              ),
              SettingsRow(
                icon: Icons.shield_moon_rounded,
                title: s.t("gate_allowlist"),
                subtitle: s.t("gate_allowlist_hint"),
                trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const GateAllowListScreen())),
              ),
            ]),
            const SizedBox(height: 20),
            SectionTitle(s.t("g_privacy")),
            SettingsGroup(children: [
              SettingsRow(
                icon: Icons.privacy_tip_rounded,
                title: s.t("privacy_policy"),
                trailing:
                    Icon(Icons.open_in_new_rounded, size: 18, color: c.muted),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final u = Uri.tryParse(AppConfig.privacyPolicyUrl);
                  if (u == null || !u.hasScheme) {
                    messenger.showSnackBar(
                        SnackBar(content: Text(s.t("no_policy"))));
                    return;
                  }
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                },
              ),
              FutureBuilder<bool>(
                future: AdService.privacyOptionsRequired(),
                builder: (_, snap) => snap.data == true
                    ? SettingsRow(
                        icon: Icons.ads_click_rounded,
                        title: s.t("ad_privacy"),
                        trailing:
                            Icon(Icons.chevron_right_rounded, color: c.muted),
                        onTap: AdService.showPrivacyOptions,
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
            const SizedBox(height: 20),
            SectionTitle(s.t("g_app")),
            SettingsGroup(children: [
              SettingsRow(
                icon: Icons.palette_rounded,
                title: s.t("theme"),
                trailing: _Choice<ThemeMode>(
                  value: themeMode,
                  values: ThemeMode.values,
                  label: themeLabel,
                  onChanged: (v) => ref.read(themeModeProvider.notifier).set(v),
                ),
              ),
              SettingsRow(
                  icon: Icons.info_outline_rounded,
                  title: s.t("version"),
                  trailing: Text(AppConfig.version,
                      style: TextStyle(color: c.muted))),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Compact dropdown shown at the end of a settings row.
class _Choice<T> extends StatelessWidget {
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const _Choice(
      {required this.value,
      required this.values,
      required this.label,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        initialValue: value,
        onSelected: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        itemBuilder: (_) => [
          for (final v in values) PopupMenuItem(value: v, child: Text(label(v)))
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label(value),
                style: TextStyle(
                    color: context.colors.brand, fontWeight: FontWeight.w600)),
            Icon(Icons.expand_more_rounded,
                size: 20, color: context.colors.brand),
          ],
        ),
      );
}
