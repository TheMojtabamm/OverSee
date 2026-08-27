import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

import "../models/vpn_config.dart";

/// Local, on-device storage of the user's configs (no server, no account).
///
/// Later-phase security note: configs that came from a locked source are best
/// stored still-locked and only opened at connect time, so extracting device
/// storage does not leak the raw config. For the base phase they are stored raw
/// for simplicity.
class ConfigStore {
  static const _key = "user_configs_v1";

  Future<List<VpnConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<VpnConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(configs.map((c) => c.toJson()).toList()));
  }

  Future<List<VpnConfig>> add(List<VpnConfig> incoming) async {
    final current = await load();
    final seen = current.map((c) => c.raw).toSet(); // de-dupe by raw
    final merged = [...current];
    for (final c in incoming) {
      if (seen.add(c.raw)) merged.add(c);
    }
    await saveAll(merged);
    return merged;
  }

  Future<List<VpnConfig>> remove(String id) async {
    final current = await load();
    current.removeWhere((c) => c.id == id);
    await saveAll(current);
    return current;
  }
}
