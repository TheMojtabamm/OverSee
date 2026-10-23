import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../data/incoming_service.dart";
import "../../providers.dart";
import "../add/add_screen.dart";
import "../add/importer.dart";
import "../configs/configs_screen.dart";

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  @override
  void initState() {
    super.initState();
    // A file opened with / shared to Oversea (e.g. a .ovsea from Telegram).
    IncomingService.listen(_onIncoming);
  }

  Future<void> _onIncoming(String text) async {
    if (!mounted) return;
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Never import silently: whatever arrived came from another app.
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.download),
        title: Text(s.t("incoming_title")),
        content: Text(s.t("incoming_body")),
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
    if (yes != true) return;

    final out = await Importer.fromText(text);
    if (!out.isOk) {
      messenger.showSnackBar(SnackBar(content: Text(s.t(out.errorKey!))));
      return;
    }
    await ref.read(configsProvider.notifier).addAll(out.configs);
    ref.read(tabProvider.notifier).state = 0;
    messenger.showSnackBar(
        SnackBar(content: Text("${s.t("imported")}: ${out.configs.length}")));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tab = ref.watch(tabProvider);
    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: const [ConfigsScreen(), AddScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.vpn_lock), label: s.t("tab_configs")),
          NavigationDestination(
              icon: const Icon(Icons.add_circle_outline),
              label: s.t("tab_add")),
        ],
      ),
    );
  }
}
