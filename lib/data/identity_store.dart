import "dart:convert";

import "../domain/creator_identity.dart";
import "config_store.dart";

/// Keeps this device's signing identity in the Keystore-backed vault. Created
/// lazily the first time something is locked or the fingerprint is shown.
class IdentityStore {
  static const _key = "creator_seed_v1";
  final Vault _vault;
  IdentityStore({Vault? vault}) : _vault = vault ?? SecureVault();

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
