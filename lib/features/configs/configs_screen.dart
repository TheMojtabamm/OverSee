import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../add/add_sheet.dart";
import "connect_flow.dart";
import "../home/home_screen.dart";
import "../subscriptions/subscriptions_screen.dart";

/// The Configs tab: every config (fastest first) and, next to it, the subscriptions that feed it.
class ConfigsScreen extends ConsumerStatefulWidget {
  const ConfigsScreen({super.key});
  @override
  ConsumerState<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends ConsumerState<ConfigsScreen> {
  bool _subs = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final configs = ref.watch(configsProvider);
    final list = configs.valueOrNull ?? const <VpnConfig>[];
    final ping = ref.watch(pingProvider);
    final selected = ref.watch(selectedConfigProvider);

    // Fastest first; untested keep their order; failed go last.
    int rank(VpnConfig c) {
      final p = ping[c.id];
      if (p == null || p == -2) return 1 << 29;
      return p < 0 ? 1 << 30 : p;
    }

    final sorted = [...list]..sort((a, b) => rank(a).compareTo(rank(b)));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: false,
                          label: Text(
                              list.isEmpty
                                  ? s.t("configs_header")
                                  : "${s.t("configs_header")}  ${list.length}",
                              maxLines: 1)),
                      ButtonSegment(
                          value: true, label: Text(s.t("subs_header"))),
                    ],
                    selected: {_subs},
                    onSelectionChanged: (v) => setState(() => _subs = v.first),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: _subs
                  ? const SubscriptionsScreen(embedded: true)
                  : configs.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text("$e")),
                      data: (_) => ListView(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (list.isNotEmpty)
                                  LinkButton(
                                    icon: Icons.bolt_rounded,
                                    label: s.t("test_speed"),
                                    onTap: () => testAllPings(ref, list),
                                  ),
                                const SizedBox(width: 6),
                                FilledButton.icon(
                                  onPressed: () => showAddSheet(context, ref),
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 38),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14),
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
                            ConfigsEmpty(
                                onAdd: () => showAddSheet(context, ref))
                          else
                            for (final cfg in sorted) ...[
                              ConfigCard(
                                  config: cfg,
                                  selected: selected?.id == cfg.id),
                              const SizedBox(height: 8),
                            ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const LinkButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

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

class ConfigsEmpty extends StatelessWidget {
  final VoidCallback onAdd;
  const ConfigsEmpty({super.key, required this.onAdd});

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
