import "dart:convert";

import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../core/log.dart";
import "../domain/vpn_config.dart";

/// Minimal secret key/value storage so the store can be tested without a device.
abstract class Vault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed storage.
class SecureVault implements Vault {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Where the pre-v2 app kept configs: plain SharedPreferences (readable as text
/// from app data). Only ever read once, to migrate, then wiped.
abstract class LegacyStore {
  Future<String?> read();
  Future<void> clear();
}

class PrefsLegacyStore implements LegacyStore {
  static const key = "user_configs_v1";
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// On-device config storage (schema v2, secure storage).
class ConfigStore {
  static const configsKey = "user_configs_v2";
  static const schemaKey = "store_schema";
  static const currentSchema = 2;

  final Vault _vault;
  final LegacyStore _legacy;

  ConfigStore({Vault? vault, LegacyStore? legacy})
      : _vault = vault ?? SecureVault(),
        _legacy = legacy ?? PrefsLegacyStore();

  Future<List<VpnConfig>> load() async {
    await _migrateIfNeeded();
    final raw = await _vault.read(configsKey);
    if (raw == null || raw.isEmpty) return [];
    return _decode(raw);
  }

  Future<void> saveAll(List<VpnConfig> configs) => _vault.write(
      configsKey, jsonEncode(configs.map((c) => c.toJson()).toList()));

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

  /// Replaces the config with the same id (an edit). No-op when it is gone.
  Future<List<VpnConfig>> update(VpnConfig edited) async {
    final current = await load();
    final i = current.indexWhere((c) => c.id == edited.id);
    if (i >= 0) current[i] = edited;
    await saveAll(current);
    return current;
  }

  Future<List<VpnConfig>> remove(String id) async {
    final current = await load();
    current.removeWhere((c) => c.id == id);
    await saveAll(current);
    return current;
  }

  // ---- migration -----------------------------------------------------------

  /// v1 → v2: move configs out of plain SharedPreferences into secure storage
  /// and wipe the plaintext copy.
  ///
  ///  * `locked:`-prefixed entries were made by the old Owner tab with the v1
  ///    format, which v3 cannot open — they are dropped.
  ///  * Old imports of locked files were stored as plain configs that only carry
  ///    the owner's ad / channel link. Those are re-flagged `locked` so they
  ///    lose Copy / Share / visible server immediately.
  Future<void> _migrateIfNeeded() async {
    final schema = int.tryParse(await _vault.read(schemaKey) ?? "") ?? 0;
    if (schema >= currentSchema) return;

    final legacyRaw = await _legacy.read();
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        final old = _decode(legacyRaw);
        final migrated = <VpnConfig>[];
        for (final c in old) {
          if (c.raw.startsWith("locked:")) continue;
          final cameFromLockedFile = c.locked ||
              (c.adText?.isNotEmpty ?? false) ||
              (c.telegramUrl?.isNotEmpty ?? false);
          migrated.add(cameFromLockedFile
              ? c.copyWith(locked: true, source: "locked", clearHost: true)
              : c);
        }
        final existing = await _vault.read(configsKey);
        final merged = [
          if (existing != null && existing.isNotEmpty) ..._decode(existing),
          ...migrated,
        ];
        await saveAll(merged);
      } catch (e) {
        // Never lose data silently, but also never keep the plaintext around
        // after a half-failed move: leave the legacy copy for the next launch.
        Log.d("config migration failed: $e");
        return;
      }
      await _legacy.clear();
    }
    await _vault.write(schemaKey, "$currentSchema");
  }

  static List<VpnConfig> _decode(String raw) => (jsonDecode(raw) as List)
      .map((e) => VpnConfig.fromJson(e as Map<String, dynamic>))
      .toList();
}
