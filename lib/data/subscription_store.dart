import "dart:convert";

import "../domain/subscription.dart";
import "config_store.dart";

/// Keeps subscriptions (their URLs may hold a secret token) in the same vault as the configs.
class SubscriptionStore {
  static const key = "subscriptions_v1";
  final Vault _vault;
  SubscriptionStore({Vault? vault}) : _vault = vault ?? SecureVault();

  Future<List<Subscription>> load() async {
    final raw = await _vault.read(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Subscription> subs) =>
      _vault.write(key, jsonEncode(subs.map((s) => s.toJson()).toList()));
}
