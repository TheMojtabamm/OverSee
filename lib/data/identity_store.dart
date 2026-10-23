import "dart:convert";

import "../domain/creator_identity.dart";
import "config_store.dart";

/// Keeps this device's signing identity in the Keystore-backed vault. Created
/// lazily the first time something is locked or the fingerprint is shown.
class IdentityStore {
  static const _key = "creator_seed_v1";
  final Vault _vault;
  IdentityStore({Vault? vault}) : _vault = vault ?? SecureVault();

  static const _entries = "gate_entries_v1";

  /// Allow-list lines for locks this device created (so the owner can copy them again).
  Future<List<String>> gateLines() async {
    final raw = await _vault.read(_entries);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addGateLine(String line) async {
    final cur = await gateLines();
    if (!cur.contains(line)) cur.add(line);
    await _vault.write(_entries, jsonEncode(cur));
  }

  Future<CreatorIdentity> load() async {
    final stored = await _vault.read(_key);
    if (stored != null) {
      try {
        final seed = base64.decode(stored);
        if (seed.length == 32) return await CreatorIdentity.fromSeed(seed);
      } catch (_) {
        // fall through and regenerate; a corrupt seed is unusable anyway
      }
    }
    final fresh = await CreatorIdentity.generate();
    await _vault.write(_key, fresh.seedBase64);
    return fresh;
  }
}
