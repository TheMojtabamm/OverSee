import "dart:convert";

import "../models/vpn_config.dart";

/// Turns a standard text config (e.g. `vless://...`, `vmess://...`, `ss://...`)
/// into a [VpnConfig]. This layer only detects the protocol and extracts
/// host/port/name for display; the [raw] field is always preserved untouched so
/// the native engine (later phase) can consume the exact original string. We
/// never rewrite the config.
class ConfigParser {
  static int _counter = 0;
  static String _nextId() =>
      "cfg_${DateTime.now().millisecondsSinceEpoch}_${_counter++}";

  /// Parses one config line. If unknown, still returns a VpnConfig with
  /// protocol=unknown so the user never loses their data (raw is kept).
  static VpnConfig? parseLine(String line,
      {String source = "manual", String? channelRef}) {
    final raw = line.trim();
    if (raw.isEmpty || raw.startsWith("#") || raw.startsWith("//")) return null;

    final scheme =
        raw.contains("://") ? raw.split("://").first.toLowerCase() : "";

    try {
      switch (scheme) {
        case "vless":
          return _fromUserinfoUri(raw, VpnProtocol.vless, source, channelRef);
        case "trojan":
          return _fromUserinfoUri(raw, VpnProtocol.trojan, source, channelRef);
        case "socks":
        case "socks5":
          return _fromUserinfoUri(raw, VpnProtocol.socks, source, channelRef);
        case "http":
        case "https":
          return _fromUserinfoUri(raw, VpnProtocol.http, source, channelRef);
        case "vmess":
          return _fromVmess(raw, source, channelRef);
        case "ss":
          return _fromShadowsocks(raw, source, channelRef);
        default:
          return VpnConfig(
            id: _nextId(),
            name: _remarkOf(raw) ?? "Unknown config",
            protocol: VpnProtocol.unknown,
            raw: raw,
            source: source,
            channelRef: channelRef,
          );
      }
    } catch (_) {
      return VpnConfig(
        id: _nextId(),
        name: "Invalid config",
        protocol: VpnProtocol.unknown,
        raw: raw,
        source: source,
        channelRef: channelRef,
      );
    }
  }

  /// Parses a multi-line blob (a subscription body or a user paste) into configs.
  static List<VpnConfig> parseMany(String text,
      {String source = "manual", String? channelRef}) {
    return text
        .split(RegExp(r"[\r\n]+"))
        .map((l) => parseLine(l, source: source, channelRef: channelRef))
        .whereType<VpnConfig>()
        .toList();
  }

  // ---- helpers -------------------------------------------------------------

  static String? _remarkOf(String uri) {
    final i = uri.indexOf("#");
    if (i == -1 || i + 1 >= uri.length) return null;
    return Uri.decodeComponent(uri.substring(i + 1));
  }

  /// Protocols shaped like `scheme://user@host:port?...#remark`
  /// (vless / trojan / socks / http).
  static VpnConfig _fromUserinfoUri(
      String raw, VpnProtocol proto, String source, String? channelRef) {
    final u = Uri.parse(raw);
    return VpnConfig(
      id: _nextId(),
      name: _remarkOf(raw) ?? (u.host.isNotEmpty ? u.host : proto.label),
      protocol: proto,
      host: u.host.isEmpty ? null : u.host,
      port: u.hasPort ? u.port : null,
      raw: raw,
      source: source,
      channelRef: channelRef,
    );
  }

  /// VMess: `vmess://<base64(json)>` — the json carries add/port/ps.
  static VpnConfig _fromVmess(String raw, String source, String? channelRef) {
    final b64 = raw.substring("vmess://".length);
    final decoded = utf8.decode(base64.decode(_padBase64(b64)));
    final j = jsonDecode(decoded) as Map<String, dynamic>;
    return VpnConfig(
      id: _nextId(),
      name: (j["ps"] as String?)?.trim().isNotEmpty == true
          ? j["ps"] as String
          : (j["add"] as String? ?? "VMess"),
      protocol: VpnProtocol.vmess,
      host: j["add"] as String?,
      port: j["port"] is int ? j["port"] as int : int.tryParse("${j["port"]}"),
      raw: raw,
      source: source,
      channelRef: channelRef,
    );
  }

  /// Shadowsocks: `ss://<base64(method:pass)>@host:port#remark` (or fully base64).
  static VpnConfig _fromShadowsocks(
      String raw, String source, String? channelRef) {
    final remark = _remarkOf(raw);
    final body = raw.substring("ss://".length).split("#").first;
    String? host;
    int? port;
    if (body.contains("@")) {
      final after = body.split("@").last; // host:port(/?...)
      final hp = after.split(RegExp(r"[/?]")).first;
      final parts = hp.split(":");
      if (parts.length >= 2) {
        host = parts[0];
        port = int.tryParse(parts[1]);
      }
    }
    return VpnConfig(
      id: _nextId(),
      name: remark ?? (host ?? "Shadowsocks"),
      protocol: VpnProtocol.shadowsocks,
      host: host,
      port: port,
      raw: raw,
      source: source,
      channelRef: channelRef,
    );
  }

  static String _padBase64(String s) {
    final clean = s.replaceAll("-", "+").replaceAll("_", "/");
    final mod = clean.length % 4;
    return mod == 0 ? clean : clean + ("=" * (4 - mod));
  }
}
