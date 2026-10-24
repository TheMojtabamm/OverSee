import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../domain/subscription.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";

/// Adds a subscription: a link that returns a list of configs. Reports the result in a
/// snack bar; the configs appear on Home.
Future<void> showAddSubscriptionDialog(
    BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<SubOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _AddSubDialog(),
  );
  if (result == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(result.ok
            ? "Added ${result.count} config${result.count == 1 ? "" : "s"}"
            : result.error!)));
}

class _AddSubDialog extends ConsumerStatefulWidget {
  const _AddSubDialog();
  @override
  ConsumerState<_AddSubDialog> createState() => _AddSubDialogState();
}

class _AddSubDialogState extends ConsumerState<_AddSubDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? "";
    if (t.trim().isNotEmpty) setState(() => _url.text = t.trim());
  }

  Future<void> _add() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final out = await ref
        .read(subscriptionsProvider.notifier)
        .add(_url.text, name: _name.text);
    if (!mounted) return;
    if (out.ok) {
      Navigator.pop(context, out);
    } else {
      setState(() {
        _busy = false;
        _error = out.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: const Text("Add a subscription"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: "Name", hintText: "Optional"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Subscription link",
                hintText: "https://…",
                suffixIcon: IconButton(
                  tooltip: "Paste",
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _busy ? null : _paste,
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(color: c.bad, fontSize: 13, height: 1.4)),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text("Cancel")),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: _busy ? null : _add,
            child: const Text("Add")),
      ],
    );
  }
}

String _ago(DateTime? t) {
  if (t == null) return "never updated";
  final d = DateTime.now().toUtc().difference(t);
  if (d.inMinutes < 1) return "updated just now";
  if (d.inMinutes < 60) return "updated ${d.inMinutes} min ago";
  if (d.inHours < 24) return "updated ${d.inHours} h ago";
  return "updated ${d.inDays} d ago";
}

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});
  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  final _busy = <String>{};
  bool _all = false;

  void _say(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _refresh(Subscription s) async {
    setState(() => _busy.add(s.id));
    final out = await ref.read(subscriptionsProvider.notifier).refresh(s.id);
    if (!mounted) return;
    setState(() => _busy.remove(s.id));
    _say(out.ok ? "Updated: ${out.count} configs" : out.error!);
  }

  Future<void> _refreshAll() async {
    setState(() => _all = true);
    final n = await ref.read(subscriptionsProvider.notifier).refreshAll();
    if (!mounted) return;
    setState(() => _all = false);
    _say("Updated $n subscription${n == 1 ? "" : "s"}");
  }

  Future<void> _rename(Subscription s) async {
    final ctrl = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename"),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text("Save")),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null) {
      await ref.read(subscriptionsProvider.notifier).rename(s.id, name);
    }
  }

  Future<void> _delete(Subscription s) async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete this subscription?"),
        content: Text(
            "Its ${s.count} config${s.count == 1 ? "" : "s"} will be removed from this device too."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 44), backgroundColor: c.bad),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(subscriptionsProvider.notifier).remove(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text("Subscriptions"),
        actions: [
          if (subs.isNotEmpty)
            IconButton(
              tooltip: "Update all",
              onPressed: _all ? null : _refreshAll,
              icon: _all
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddSubscriptionDialog(context, ref),
        backgroundColor: c.brand,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add"),
      ),
      body: subs.isEmpty
          ? EmptyState(
              icon: Icons.sync_rounded,
              title: "No subscriptions",
              body:
                  "A subscription is a link that gives you a list of configs. Add it once and update the list whenever you like.",
              actions: [
                FilledButton.icon(
                  onPressed: () => showAddSubscriptionDialog(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Add a subscription"),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
              children: [
                for (final s in subs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                        child: Row(children: [
                          const IconTile(Icons.sync_rounded, size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                    "${s.count} config${s.count == 1 ? "" : "s"}  ·  ${_ago(s.updatedAt)}",
                                    style: TextStyle(
                                        color: c.muted, fontSize: 12.5)),
                                if (s.error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(s.error!,
                                        style: TextStyle(
                                            color: c.bad, fontSize: 12.5)),
                                  ),
                              ],
                            ),
                          ),
                          if (_busy.contains(s.id))
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          else
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz_rounded,
                                  color: c.muted),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              onSelected: (v) {
                                switch (v) {
                                  case "refresh":
                                    _refresh(s);
                                  case "rename":
                                    _rename(s);
                                  case "delete":
                                    _delete(s);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: "refresh",
                                    child: Text("Update now")),
                                PopupMenuItem(
                                    value: "rename", child: Text("Rename")),
                                PopupMenuItem(
                                    value: "delete", child: Text("Delete")),
                              ],
                            ),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
