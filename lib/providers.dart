import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "data/config_store.dart";
import "data/exit_ip.dart";
import "data/identity_store.dart";
import "data/settings_store.dart";
import "data/subscription_service.dart";
import "data/subscription_store.dart";
import "data/tunnel_service.dart";
import "domain/subscription.dart";
import "domain/tunnel_settings.dart";
import "domain/vpn_config.dart";
import "domain/xray_config_builder.dart";

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

  Future<void> saveEdited(VpnConfig edited) async {
    state = AsyncData(await _store.update(edited));
  }

  /// Swaps the whole list (a subscription refresh).
  Future<void> replaceAll(List<VpnConfig> configs) async {
    await _store.saveAll(configs);
    state = AsyncData(configs);
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

/// Loopback probe proxy of the running core (random per connection, memory only).
final probeProvider = StateProvider<ProbeEndpoint?>((ref) => null);

/// Exit IP + country seen through the tunnel; null while not connected or unavailable.
final exitInfoProvider = FutureProvider.autoDispose<ExitInfo?>((ref) async {
  // Only the phase matters; the state itself changes every second (traffic counters).
  final phase =
      ref.watch(tunnelStateProvider.select((s) => s.valueOrNull?.phase));
  final probe = ref.watch(probeProvider);
  if (phase != TunnelPhase.connected || probe == null) return null;
  return fetchExitInfo(probe);
});

/// Which saved config the user last asked to connect.
final activeConfigIdProvider = StateProvider<String?>((ref) => null);

/// The config the tunnel was started with (null when none / it was removed).
final activeConfigProvider = Provider<VpnConfig?>((ref) {
  final id = ref.watch(activeConfigIdProvider);
  final list = ref.watch(configsProvider).valueOrNull ?? const <VpnConfig>[];
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

/// UTC day of the gate token the running tunnel was started with (null = not gated).
final tunnelTokenDayProvider = StateProvider<int?>((ref) => null);

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

// ---- subscriptions ---------------------------------------------------------

final subscriptionStoreProvider =
    Provider<SubscriptionStore>((ref) => SubscriptionStore());
final subscriptionServiceProvider =
    Provider<SubscriptionService>((ref) => SubscriptionService());

/// What a subscription add / refresh did, for the UI to report.
class SubOutcome {
  final int count;
  final String? error;
  const SubOutcome.ok(this.count) : error = null;
  const SubOutcome.fail(this.error) : count = 0;
  bool get ok => error == null;
}

class SubscriptionsNotifier extends AsyncNotifier<List<Subscription>> {
  SubscriptionStore get _store => ref.read(subscriptionStoreProvider);

  @override
  Future<List<Subscription>> build() => _store.load();

  List<Subscription> get _now => state.valueOrNull ?? const [];

  Future<void> _save(List<Subscription> subs) async {
    await _store.save(subs);
    state = AsyncData(subs);
  }

  Future<SubOutcome> add(String url, {String? name}) async {
    final u = url.trim();
    if (!Subscription.isValidUrl(u)) {
      return const SubOutcome.fail("Enter a full link starting with https://");
    }
    if (_now.any((s) => s.url == u)) {
      return const SubOutcome.fail("This subscription is already added");
    }
    final sub = Subscription(
      id: "sub_${DateTime.now().millisecondsSinceEpoch}",
      name: (name ?? "").trim().isEmpty
          ? Subscription.nameFromUrl(u)
          : name!.trim(),
      url: u,
    );
    final out = await _fetchInto(sub);
    if (out.ok) {
      // _fetchInto saved the configs; keep the subscription itself only if it worked.
    }
    return out;
  }

  Future<SubOutcome> refresh(String id) async {
    final sub = _now.where((s) => s.id == id).firstOrNull;
    if (sub == null) return const SubOutcome.fail("Subscription not found");
    return _fetchInto(sub);
  }

  /// Refreshes every subscription; returns how many succeeded.
  Future<int> refreshAll() async {
    var ok = 0;
    for (final s in [..._now]) {
      if ((await _fetchInto(s)).ok) ok++;
    }
    return ok;
  }

  Future<SubOutcome> _fetchInto(Subscription sub) async {
    final isNew = !_now.any((s) => s.id == sub.id);
    try {
      final body =
          await ref.read(subscriptionServiceProvider).fetch(Uri.parse(sub.url));
      final fetched =
          Subscription.parseBody(body, subId: sub.id, subName: sub.name);
      if (fetched.isEmpty) {
        throw const SubscriptionFetchException(
            "No supported configs found in that list");
      }
      final current = ref.read(configsProvider).valueOrNull ?? const [];
      final merged =
          Subscription.merge(current: current, subId: sub.id, fetched: fetched);
      await ref.read(configsProvider.notifier).replaceAll(merged);
      final count = merged.where((c) => c.channelRef == sub.id).length;
      final done = sub.copyWith(
          updatedAt: DateTime.now().toUtc(), count: count, clearError: true);
      await _save(isNew
          ? [..._now, done]
          : [for (final s in _now) s.id == sub.id ? done : s]);
      return SubOutcome.ok(count);
    } on SubscriptionFetchException catch (e) {
      if (!isNew) {
        await _save([
          for (final s in _now)
            s.id == sub.id ? s.copyWith(error: e.message) : s
        ]);
      }
      return SubOutcome.fail(e.message);
    } catch (_) {
      if (!isNew) {
        await _save([
          for (final s in _now)
            s.id == sub.id ? s.copyWith(error: "Could not read the list") : s
        ]);
      }
      return const SubOutcome.fail("Could not read the list");
    }
  }

  Future<void> rename(String id, String name) => _save([
        for (final s in _now)
          s.id == id
              ? s.copyWith(name: name.trim().isEmpty ? s.name : name.trim())
              : s
      ]);

  /// Deletes the subscription and every config that came from it.
  Future<void> remove(String id) async {
    final current = ref.read(configsProvider).valueOrNull ?? const [];
    await ref
        .read(configsProvider.notifier)
        .replaceAll(current.where((c) => c.channelRef != id).toList());
    await _save(_now.where((s) => s.id != id).toList());
  }
}

final subscriptionsProvider =
    AsyncNotifierProvider<SubscriptionsNotifier, List<Subscription>>(
        SubscriptionsNotifier.new);
