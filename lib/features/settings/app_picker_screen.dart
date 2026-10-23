import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/strings.dart";
import "../../data/tunnel_service.dart";
import "../../providers.dart";

class AppPickerScreen extends ConsumerStatefulWidget {
  const AppPickerScreen({super.key});
  @override
  ConsumerState<AppPickerScreen> createState() => _AppPickerScreenState();
}

class _AppPickerScreenState extends ConsumerState<AppPickerScreen> {
  List<InstalledApp>? _apps;
  String _q = "";

  @override
  void initState() {
    super.initState();
    ref.read(tunnelServiceProvider).listApps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final chosen = (settings?.apps ?? const <String>[]).toSet();
    final apps = (_apps ?? const <InstalledApp>[])
        .where((a) => a.label.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(s.t("choose_apps"))),
      body: _apps == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: s.t("search"),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (_, i) {
                      final a = apps[i];
                      return CheckboxListTile(
                        title: Text(a.label),
                        subtitle: Text(a.package,
                            style: Theme.of(context).textTheme.bodySmall),
                        value: chosen.contains(a.package),
                        onChanged: (v) =>
                            ref.read(settingsProvider.notifier).change((c) {
                          final next = {...c.apps};
                          v == true
                              ? next.add(a.package)
                              : next.remove(a.package);
                          return c.copyWith(apps: next.toList());
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
