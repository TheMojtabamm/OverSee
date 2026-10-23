import "package:shared_preferences/shared_preferences.dart";

import "../domain/tunnel_settings.dart";

/// Non-secret preferences. (Configs live in the secure ConfigStore.)
class SettingsStore {
  static const _settings = "tunnel_settings_v1";
  static const _disclosure = "vpn_disclosure_accepted_v1";
  static const _firstConnectDone = "first_connect_done_v1";

  Future<TunnelSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_settings);
    return s == null ? const TunnelSettings() : TunnelSettings.fromJson(s);
  }

  Future<void> save(TunnelSettings s) async =>
      (await SharedPreferences.getInstance()).setString(_settings, s.toJson());

  static const _trusted = "trusted_creators_v1";

  /// Fingerprints of creators the user chose to trust (e.g. a channel's official ID).
  Future<Set<String>> trustedCreators() async =>
      ((await SharedPreferences.getInstance()).getStringList(_trusted) ??
              const [])
          .toSet();

  Future<void> setTrusted(String fingerprint, bool trusted) async {
    final p = await SharedPreferences.getInstance();
    final cur = (p.getStringList(_trusted) ?? const <String>[]).toSet();
    trusted ? cur.add(fingerprint) : cur.remove(fingerprint);
    await p.setStringList(_trusted, cur.toList());
  }

  Future<bool> disclosureAccepted() async =>
      (await SharedPreferences.getInstance()).getBool(_disclosure) ?? false;

  Future<void> acceptDisclosure() async =>
      (await SharedPreferences.getInstance()).setBool(_disclosure, true);

  Future<bool> firstConnectDone() async =>
      (await SharedPreferences.getInstance()).getBool(_firstConnectDone) ??
      false;

  Future<void> markFirstConnectDone() async =>
      (await SharedPreferences.getInstance()).setBool(_firstConnectDone, true);
}
