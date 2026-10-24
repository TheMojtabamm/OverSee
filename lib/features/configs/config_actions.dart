import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../domain/config_draft.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "../configs/connect_flow.dart";
import "../configs/share_sheet.dart";
import "../editor/config_editor_screen.dart";

/// The "…" menu of one config as a bottom sheet: use, test, edit, share, delete.
///
/// Locked configs can't be edited or re-shared: editing would reveal them and re-sharing
/// would allow re-locking under someone else's name.
Future<void> showConfigActions(
    BuildContext context, WidgetRef ref, VpnConfig cfg) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => _Actions(cfg: cfg, host: context, ref: ref),
  );
}

class _Actions extends StatelessWidget {
  final VpnConfig cfg;
  final BuildContext host;
  final WidgetRef ref;
  const _Actions({required this.cfg, required this.host, required this.ref});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = context.colors;

    Widget item(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 22, color: color ?? c.brand),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15, color: color)),
          ]),
        ),
      );
    }

    void close() => Navigator.pop(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cfg.name.isEmpty ? (cfg.host ?? "—") : cfg.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 5, children: [
              Pill(cfg.protocol.label),
              if (cfg.locked)
                Pill(s.t("locked"), icon: Icons.lock_rounded, color: c.brand),
            ]),
            const SizedBox(height: 8),
            item(Icons.check_circle_outline_rounded, s.t("act_use"), () {
              close();
              ref.read(selectedConfigIdProvider.notifier).select(cfg.id);
            }),
            item(Icons.bolt_rounded, s.t("act_ping"), () {
              close();
              testPing(ref, cfg);
            }),
            if (!cfg.locked && ConfigDraft.fromLink(cfg.raw) != null)
              item(Icons.edit_outlined, s.t("act_edit"), () {
                close();
                Navigator.of(host).push(MaterialPageRoute<void>(
                    builder: (_) => ConfigEditorScreen(existing: cfg)));
              }),
            if (!cfg.locked)
              item(Icons.ios_share_rounded, s.t("act_share"), () {
                close();
                showShareSheet(host, cfg);
              }),
            item(Icons.delete_outline_rounded, s.t("act_delete"), () async {
              close();
              final ok = await showDialog<bool>(
                context: host,
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
            }, color: c.bad),
          ],
        ),
      ),
    );
  }
}
