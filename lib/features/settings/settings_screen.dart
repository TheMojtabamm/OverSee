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
          DnsPreset.tunnel => "Off (plain DNS)",
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
              ChoiceRow<DnsPreset>(
                icon: Icons.dns_rounded,
                title: s.t("dns"),
                value: settings.dns,
                values: DnsPreset.values,
                label: dnsLabel,
                hint: (d) => d == DnsPreset.tunnel
                    ? s.t("dns_opt_plain")
                    : s.t("dns_opt_doh"),
                sheetNote: s.t("dns_hint"),
                onChanged: (v) => notifier.change((x) => x.copyWith(dns: v)),
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
              ChoiceRow<SplitMode>(
                icon: Icons.apps_rounded,
                title: s.t("split"),
                value: settings.splitMode,
                values: SplitMode.values,
                label: splitLabel,
                onChanged: (v) =>
                    notifier.change((x) => x.copyWith(splitMode: v)),
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
              ChoiceRow<ThemeMode>(
                icon: Icons.palette_rounded,
                title: s.t("theme"),
                value: themeMode,
                values: ThemeMode.values,
                label: themeLabel,
                onChanged: (v) => ref.read(themeModeProvider.notifier).set(v),
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

/// A settings row that shows the current value and opens a bottom sheet with the options
/// (radio list, optional one-line hint per option) when tapped.
class ChoiceRow<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final String Function(T)? hint;
  final String? sheetNote;
  final ValueChanged<T> onChanged;
  const ChoiceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.hint,
    this.sheetNote,
  });

  Future<void> _open(BuildContext context) async {
    final c = context.colors;
    final picked = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(title,
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (sheetNote != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(sheetNote!,
                      style: TextStyle(color: c.muted, height: 1.4)),
                ),
              for (final v in values)
                ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  title: Text(label(v),
                      style: TextStyle(
                          fontWeight:
                              v == value ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: hint == null
                      ? null
                      : Text(hint!(v),
                          style: TextStyle(fontSize: 12.5, color: c.muted)),
                  trailing: v == value
                      ? Icon(Icons.check_circle_rounded, color: c.brand)
                      : Icon(Icons.circle_outlined, color: c.muted),
                  onTap: () => Navigator.pop(ctx, v),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
        icon: icon,
        title: title,
        subtitle: label(value),
        trailing: Icon(Icons.chevron_right_rounded,
            color: context.colors.muted, size: 22),
        onTap: () => _open(context),
      );
}
