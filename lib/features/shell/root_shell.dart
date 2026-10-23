import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../providers.dart";
import "../add/add_screen.dart";
import "../configs/configs_screen.dart";

class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
