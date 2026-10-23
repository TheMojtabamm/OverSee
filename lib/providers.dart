import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "data/config_store.dart";
import "domain/vpn_config.dart";

final configStoreProvider = Provider<ConfigStore>((ref) => ConfigStore());

/// The user's saved configs. Mutations go through this notifier so every screen
/// stays in sync without manual reloads.
class ConfigsNotifier extends AsyncNotifier<List<VpnConfig>> {
  ConfigStore get _store => ref.read(configStoreProvider);

  @override
  Future<List<VpnConfig>> build() => _store.load();

  Future<void> addAll(List<VpnConfig> incoming) async {
    state = AsyncData(await _store.add(incoming));
  }

  Future<void> remove(String id) async {
    state = AsyncData(await _store.remove(id));
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_store.load);
  }
}

final configsProvider = AsyncNotifierProvider<ConfigsNotifier, List<VpnConfig>>(
    ConfigsNotifier.new);

/// Selected bottom-nav tab.
final tabProvider = StateProvider<int>((ref) => 0);

/// null = follow the device language.
final localeProvider = StateProvider<Locale?>((ref) => null);
