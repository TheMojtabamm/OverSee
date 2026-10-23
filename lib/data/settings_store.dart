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
