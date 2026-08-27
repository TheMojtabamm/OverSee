/// A single config (one server / one protocol) the user can connect to.
///
/// This model is intentionally protocol-agnostic: every protocol (VLESS, VMess,
/// Trojan, Shadowsocks, SOCKS, HTTP, OpenVPN, IKEv2, ...) is stored in the same
/// shape. The [raw] field holds the original config string/blob verbatim so the
/// native tunnel engine (added in a later phase) can consume it unchanged. This
/// layer only handles management, display, and locking — never the tunnel itself.
enum VpnProtocol {
  vless,
  vmess,
  trojan,
  shadowsocks,
  socks,
  http,
  openvpn,
  ikev2,
  l2tp,
  unknown;

  String get label => switch (this) {
        VpnProtocol.vless => "VLESS",
        VpnProtocol.vmess => "VMess",
        VpnProtocol.trojan => "Trojan",
        VpnProtocol.shadowsocks => "Shadowsocks",
        VpnProtocol.socks => "SOCKS",
        VpnProtocol.http => "HTTP",
        VpnProtocol.openvpn => "OpenVPN",
        VpnProtocol.ikev2 => "IKEv2",
        VpnProtocol.l2tp => "L2TP",
        VpnProtocol.unknown => "Unknown",
      };
}

class VpnConfig {
  final String id; // internal id (for storage/removal)
  final String name; // display name (remark)
  final VpnProtocol protocol;
  final String? host;
  final int? port;

  /// The original config string/blob, kept exactly as entered/imported. This is
  /// what gets handed to the native engine later. For URL-style configs it is the
  /// URI; for OpenVPN it is the full .ovpn text.
  final String raw;

  /// Where the config came from: manual, subscription, or a free-config feed.
  final String source;

  /// If it came from a feed channel, that channel's ref (for stats/attribution).
  final String? channelRef;

  const VpnConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.raw,
    required this.source,
    this.host,
    this.port,
    this.channelRef,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "protocol": protocol.name,
        "host": host,
        "port": port,
        "raw": raw,
        "source": source,
        "channelRef": channelRef,
      };

  factory VpnConfig.fromJson(Map<String, dynamic> j) => VpnConfig(
        id: j["id"] as String,
        name: (j["name"] as String?) ?? "Untitled",
        protocol: VpnProtocol.values.firstWhere(
          (p) => p.name == j["protocol"],
          orElse: () => VpnProtocol.unknown,
        ),
        host: j["host"] as String?,
        port: j["port"] as int?,
        raw: j["raw"] as String,
        source: (j["source"] as String?) ?? "manual",
        channelRef: j["channelRef"] as String?,
      );
}
