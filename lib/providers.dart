import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "data/config_store.dart";
import "data/identity_store.dart";
import "data/settings_store.dart";
import "data/tunnel_service.dart";
import "domain/tunnel_settings.dart";
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

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    var alive = true;
    ref.onDispose(() => alive = false);
    ref.read(settingsStoreProvider).themeMode().then((m) {
      if (!alive) return;
      state = switch (m) {
        "light" => ThemeMode.light,
        "dark" => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    });
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    await ref.read(settingsStoreProvider).setThemeMode(switch (m) {
          ThemeMode.light => "light",
          ThemeMode.dark => "dark",
          ThemeMode.system => null,
        });
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// The config the big button connects. Persisted; falls back to the first config.
class SelectedConfigNotifier extends Notifier<String?> {
  @override
  String? build() {
    var alive = true;
    ref.onDispose(() => alive = false);
    ref.read(settingsStoreProvider).selectedConfig().then((id) {
      if (id != null && alive && state == null) state = id;
    });
    return null;
  }

  Future<void> select(String? id) async {
    state = id;
    await ref.read(settingsStoreProvider).setSelectedConfig(id);
  }
}

final selectedConfigIdProvider =
    NotifierProvider<SelectedConfigNotifier, String?>(
        SelectedConfigNotifier.new);

/// The config the home screen acts on: the selected one if it still exists, else the first.
final selectedConfigProvider = Provider<VpnConfig?>((ref) {
  final list = ref.watch(configsProvider).valueOrNull ?? const <VpnConfig>[];
  if (list.isEmpty) return null;
  final id = ref.watch(selectedConfigIdProvider);
  return list.firstWhere((c) => c.id == id, orElse: () => list.first);
});

/// When the current connection came up (for the timer); null when not connected.
class ConnectedSinceNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.listen(tunnelStateProvider, (_, next) {
      final phase = next.valueOrNull?.phase;
      if (phase == TunnelPhase.connected) {
        state ??= DateTime.now();
      } else {
        state = null;
      }
    }, fireImmediately: true);
    return null;
  }
}

final connectedSinceProvider =
    NotifierProvider<ConnectedSinceNotifier, DateTime?>(
        ConnectedSinceNotifier.new);

final onboardedProvider =
    FutureProvider<bool>((ref) => ref.read(settingsStoreProvider).onboarded());

final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());
final tunnelServiceProvider = Provider<TunnelService>((ref) => TunnelService());

class SettingsNotifier extends AsyncNotifier<TunnelSettings> {
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  Future<TunnelSettings> build() => _store.load();

  Future<void> change(TunnelSettings Function(TunnelSettings) change) async {
    final next = change(state.valueOrNull ?? const TunnelSettings());
    state = AsyncData(next);
    await _store.save(next);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, TunnelSettings>(
        SettingsNotifier.new);

/// Live tunnel state from the native VpnService.
final tunnelStateProvider = StreamProvider<TunnelState>((ref) async* {
  final svc = ref.watch(tunnelServiceProvider);
  yield await svc.status();
  yield* svc.states;
});

/// Which saved config the user last asked to connect.
final activeConfigIdProvider = StateProvider<String?>((ref) => null);

final identityStoreProvider = Provider<IdentityStore>((ref) => IdentityStore());

class TrustedCreatorsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() =>
      ref.read(settingsStoreProvider).trustedCreators();

  Future<void> setTrusted(String fingerprint, bool trusted) async {
    await ref.read(settingsStoreProvider).setTrusted(fingerprint, trusted);
    state = AsyncData(await ref.read(settingsStoreProvider).trustedCreators());
  }
}

final trustedCreatorsProvider =
    AsyncNotifierProvider<TrustedCreatorsNotifier, Set<String>>(
        TrustedCreatorsNotifier.new);

/// Per-config latency in ms: absent = untested, -1 = failed, -2 = testing.
class PingNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void set(String id, int ms) => state = {...state, id: ms};
  void clear() => state = const {};
}

final pingProvider =
    NotifierProvider<PingNotifier, Map<String, int>>(PingNotifier.new);
