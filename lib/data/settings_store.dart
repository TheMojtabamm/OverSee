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

  static const _selected = "selected_config_v1";
  static const _theme = "theme_v1";
  static const _onboarded = "onboarded_v1";

  Future<String?> selectedConfig() async =>
      (await SharedPreferences.getInstance()).getString(_selected);
  Future<void> setSelectedConfig(String? id) async {
    final p = await SharedPreferences.getInstance();
    id == null ? await p.remove(_selected) : await p.setString(_selected, id);
  }

  /// "light", "dark", or null = follow the device.
  Future<String?> themeMode() async =>
      (await SharedPreferences.getInstance()).getString(_theme);
  Future<void> setThemeMode(String? mode) async {
    final p = await SharedPreferences.getInstance();
    mode == null ? await p.remove(_theme) : await p.setString(_theme, mode);
  }

  Future<bool> onboarded() async =>
      (await SharedPreferences.getInstance()).getBool(_onboarded) ?? false;
  Future<void> setOnboarded() async =>
      (await SharedPreferences.getInstance()).setBool(_onboarded, true);

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
