import "package:flutter/material.dart";

/// Minimal fa/en string table. Persian is the primary audience, so every key
/// must exist in both languages (enforced by a unit test).
class S {
  final Locale locale;
  const S(this.locale);

  static const supportedLocales = [Locale("en")];
  static const LocalizationsDelegate<S> delegate = _SDelegate();

  static S of(BuildContext context) => Localizations.of<S>(context, S)!;

  String t(String key) =>
      (table[locale.languageCode] ?? table["en"]!)[key] ??
      table["en"]![key] ??
      key;

  static const Map<String, Map<String, String>> table = {
    "en": {
      "tab_configs": "Configs",
      "tab_add": "Add",
      "configs_title": "Configs",
      "empty_title": "No configs yet.",
      "empty_hint":
          "Open the Add tab to paste a config or import a locked file.",
      "locked": "Locked",
      "no_tls": "Not encrypted",
      "connect_ok": "Connected",
      "channel": "Channel",
      "open_channel": "Open Channel",
      "cancel": "Cancel",
      "continue": "Continue",
      "add_title": "Add config",
      "add_hint": "vless:// vmess:// trojan:// ss://  …",
      "paste": "Paste",
      "add": "Add",
      "import_locked": "Import locked file (.ovsea)",
      "clipboard_empty": "Clipboard is empty.",
      "no_xray":
          "No supported Xray config found (VLESS / VMess / Trojan / Shadowsocks).",
      "no_key": "This build cannot open locked files.",
      "share": "Share",
      "copy": "Copy",
      "copied": "Config copied",
      "qr": "QR code",
      "hide_qr": "Hide QR",
      "lock_title": "Lock (export as protected file)",
      "lock_sub": "Only Oversea can open it. Shared as a file.",
      "ad_text": "Ad text (shown to whoever opens it)",
      "tg_url": "Telegram channel URL",
      "lock_share": "Lock & share file",
      "settings": "Settings",
      "sponsored": "Sponsored",
      "sponsored_note":
          "Message from the owner of this config. Not from Oversea.",
      "status_disconnected": "Disconnected",
      "status_connecting": "Connecting…",
      "status_connected": "Connected",
      "exit_ip": "Exit IP",
      "exit_ip_checking": "Checking exit IP…",
      "exit_ip_failed": "Exit IP unavailable",
      "status_blocked": "Blocked — connection lost",
      "status_error": "Connection failed",
      "disconnect": "Disconnect",
      "vpn_denied": "VPN permission was not granted.",
      "unsupported": "This config type is not supported.",
      "connect_failed": "Could not connect.",
      "invalid_tg": "Channel link must be an https://t.me/… link.",
      "disclosure_title": "VPN connection",
      "disclosure_body":
          "Oversea uses Android's VPN service to route your device's internet traffic through the server in the config you choose. Your traffic is encrypted between your phone and that server.\n\nOversea does not record, store or sell your browsing activity. The server you pick is run by the config's owner, so only connect to servers you trust.\n\nThe app shows ads (Google AdMob), which may use your advertising ID if you consent.",
      "agree": "Agree & continue",
      "dns": "Private DNS (DoH)",
      "dns_hint":
          "Lookups always go through the tunnel. DoH encrypts them inside it.",
      "fragment": "TLS fragmentation",
      "fragment_hint": "Helps on networks that filter by SNI.",
      "ipv6": "IPv6",
      "ipv6_hint": "Off: IPv6 is blocked inside the tunnel (no leaks).",
      "bypass_lan": "Bypass local network",
      "kill_switch": "Kill switch",
      "kill_switch_hint":
          "If the connection drops, block traffic instead of leaking.",
      "system_vpn": "Always-on VPN",
      "system_vpn_hint": "Opens Android's VPN settings",
      "split": "Per-app VPN",
      "split_all": "All apps",
      "split_allow": "Only selected",
      "split_deny": "Except selected",
      "choose_apps": "Choose apps",
      "search": "Search",
      "privacy_policy": "Privacy policy",
      "ad_privacy": "Ad privacy options",
      "no_policy": "No policy URL configured in this build.",
      "creator_verified": "Verified creator",
      "creator_unknown": "Creator (not trusted)",
      "creator_unsigned": "Unsigned file — creator unknown",
      "trust": "Trust",
      "untrust": "Remove trust",
      "your_creator_id": "Your creator ID",
      "your_creator_hint":
          "Publish this in your channel so followers can recognise your official files.",
      "test_all": "Test all",
      "ms": "ms",
      "failed": "failed",
      "gate_title": "Server gate (anti-theft)",
      "gate_hint":
          "The server only accepts Oversea. A decoded link won't work in other apps. Needs the gate on your server and a WebSocket/HTTPUpgrade config.",
      "gate_unsupported": "Gate needs a WebSocket or HTTPUpgrade transport.",
      "gate_line_title": "Allow this lock on your server",
      "gate_line_body":
          "Add this line to the gate's allow-list. Delete it later to revoke this lock and every copy of it.",
      "gate_step1": "Copy the line below",
      "gate_step2":
          "On your server run the command (or open Locks in `oversee` and press a), then paste",
      "gate_step3": "Share the file. It only connects after this step.",
      "share_file": "Share the file",
      "copy_line": "Copy line",
      "copy_cmd": "Copy command",
      "copied_short": "Copied",
      "gate_allowlist": "Gate allow-list",
      "gate_allowlist_hint": "Lines for the locks you created",
      "gate_allowlist_empty": "You have not created any gated locks yet.",
      "expires": "File expires",
      "exp_1d": "In 24 hours",
      "exp_7d": "In 7 days",
      "exp_30d": "In 30 days",
      "exp_never": "Never",
      "file_expired": "This file has expired. Ask the owner for a new one.",
      "expired": "Expired",
      "import_invalid": "Invalid or unsupported file.",
      "import_too_big": "That is too large to be a config.",
      "incoming_title": "Import into Oversea?",
      "incoming_body":
          "A file or text was shared with Oversea. Only import files from sources you trust.",
      "imported": "Imported",
      "tab_home": "Home",
      "tab_settings": "Settings",
      "app_tagline": "Fast, private tunnel",
      "hero_tap_connect": "Tap to connect",
      "hero_tap_disconnect": "Tap to disconnect",
      "hero_switch_to": "Tap to switch to the selected server",
      "hero_add_first": "Add a config to get started",
      "hero_blocked": "Traffic is blocked until the VPN is back",
      "selected_server": "Selected",
      "uploaded": "Upload",
      "downloaded": "Download",
      "your_configs": "Your configs",
      "test_speed": "Test speed",
      "remove": "Remove",
      "remove_title": "Remove this config?",
      "remove_body": "It will be deleted from this device.",
      "details": "Details",
      "empty_cta_add": "Add a config",
      "empty_cta_import": "Import a file",
      "add_subtitle":
          "Paste links, import a locked file, or scan from another app.",
      "add_from_clipboard": "Paste from clipboard",
      "add_from_file": "Import locked file",
      "add_manual": "Or paste links here",
      "add_btn": "Add to my configs",
      "supported_protocols": "VLESS · VMess · Trojan · Shadowsocks",
      "g_connection": "Connection",
      "g_routing": "Routing",
      "g_privacy": "Privacy & ads",
      "g_app": "App",
      "g_creator": "Creator tools",
      "theme": "Appearance",
      "theme_system": "System",
      "theme_light": "Light",
      "theme_dark": "Dark",
      "about": "About",
      "version": "Version",
      "splitrow": "Apps using the VPN",
      "ob_skip": "Skip",
      "ob_next": "Next",
      "ob_start": "Get started",
      "ob1_title": "One tap, private tunnel",
      "ob1_body":
          "Add a config and connect in a single tap. Your traffic goes through the server you choose.",
      "ob2_title": "Locked files, safe sharing",
      "ob2_body":
          "Share configs as protected files. Only Oversea opens them, and you can attach your channel.",
      "ob3_title": "You stay in control",
      "ob3_body":
          "No account, no logs. A kill switch blocks traffic if the connection ever drops.",
      "connected_for": "Connected for",
      "clipboard_hint": "Links in your clipboard are added in one tap.",
      "share_plain": "Link",
      "share_locked": "Locked file",
      "settings_creator_id_copied": "Creator ID copied",
      "clipboard_added": "Added from clipboard",
      "gate_off_warning":
          "Without the gate, anyone who decodes this file can use the config in any app. Keep it on unless you know why not.",
      "gate_unsupported_notice":
          "This config can't use the server gate (it needs a WebSocket or HTTPUpgrade transport). Anyone who decodes the file could use it in any app.",
      "gate_unavailable_notice":
          "This build has no gate key, so the lock only hides the config inside the app. A decoded config would work in any app.",
      "connect_failed_gated":
          "Could not connect. Check that your phone's date and time are correct, and that the file hasn't been revoked by its owner.",
    },
  };
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();
  @override
  bool isSupported(Locale locale) =>
      S.supportedLocales.any((l) => l.languageCode == locale.languageCode);
  @override
  Future<S> load(Locale locale) async => S(locale);
  @override
  bool shouldReload(covariant LocalizationsDelegate<S> old) => false;
}
