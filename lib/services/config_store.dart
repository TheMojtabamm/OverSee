import "dart:convert";

import "package:flutter_secure_storage/flutter_secure_storage.dart";

import "../models/vpn_config.dart";

/// On-device storage of the user's configs. Backed by Android Keystore-protected
/// secure storage so configs (especially ones imported from locked files) are
/// not readable as plain text from app data.
class ConfigStore {
  static const _key = "user_configs_v2";
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<List<VpnConfig>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<VpnConfig> configs) => _storage.write(
      key: _key, value: jsonEncode(configs.map((c) => c.toJson()).toList()));

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
