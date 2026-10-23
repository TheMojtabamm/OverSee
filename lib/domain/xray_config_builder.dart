import "dart:convert";

/// Tunnel behaviour that is independent of which server is used.
/// A loopback-only, password-protected HTTP proxy inside the core. It is how the app
/// (which is excluded from its own VPN) looks at the world *through* the tunnel, e.g. to
/// show the exit IP. Random port and credentials per connection; kept in memory only.
class ProbeEndpoint {
  final int port;
  final String user;
  final String pass;
  const ProbeEndpoint(this.port, this.user, this.pass);
}

class TunnelOptions {
  /// DNS-over-HTTPS endpoints. Queried *through* the tunnel, so the ISP never
  /// sees the lookups. Use IP-literal URLs so DoH itself needs no resolver.
  final List<String> dohServers;

  /// Split the TLS ClientHello into small pieces to the server (defeats simple
  /// SNI/DPI filters). Needs a TLS/Reality outbound.
  final bool fragment;

  /// When false, IPv6 is still routed into the tunnel but dropped there, so
  /// there is no IPv6 leak outside the VPN.
  final bool ipv6;

  /// Keep local-network traffic (router, printers, casting) off the tunnel.
  final bool bypassLan;

  final int mtu;

  /// Token for a gated server (see GateToken). Sent as a header on WebSocket /
  /// HTTPUpgrade connections; ignored for other transports.
  final String? gateToken;

  /// Adds the loopback probe proxy (see [ProbeEndpoint]).
  final ProbeEndpoint? probe;

  /// Drops UDP/443 (QUIC / HTTP/3) so apps fall back to TCP at once. Many servers and CDNs
  /// can't carry QUIC over the proxy, and Google's apps and Chrome then hang on it.
  final bool blockQuic;

  /// Xray log level ("warning" normally; "info"/"debug" for diagnostics).
  final String logLevel;

  const TunnelOptions({
    this.dohServers = const [
      "https://1.1.1.1/dns-query",
      "https://8.8.8.8/dns-query",
    ],
    this.fragment = false,
    this.ipv6 = false,
    this.bypassLan = true,
    this.mtu = 1500,
    this.gateToken,
    this.probe,
    this.logLevel = "warning",
    this.blockQuic = true,
  });
}

class UnsupportedConfigException implements Exception {
  final String message;
  const UnsupportedConfigException(this.message);
  @override
  String toString() => "UnsupportedConfigException: $message";
}

/// Turns a share link (`vless://`, `vmess://`, `trojan://`, `ss://`) into a
/// complete Xray-core JSON config that reads packets from the Android TUN file
/// descriptor (the `tun` inbound; the fd is handed to the core natively).
///
/// The output is validated against Xray-core's own config loader by
/// `tool/validate_xray_config` (see test/xray_config_builder_test.dart for the
/// fixtures it checks).
class XrayConfigBuilder {
  XrayConfigBuilder._();

  static const _lan = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "127.0.0.0/8",
    "169.254.0.0/16",
    "100.64.0.0/10",
    "fc00::/7",
    "fe80::/10",
  ];

  static String build(String raw,
          [TunnelOptions opts = const TunnelOptions()]) =>
      const JsonEncoder.withIndent("  ").convert(buildMap(raw, opts));

  static Map<String, dynamic> buildMap(String raw,
      [TunnelOptions opts = const TunnelOptions()]) {
    final link = raw.trim();
    final proxy = _outbound(link);
    final host = _serverHost(proxy);
    if (opts.gateToken != null) _applyGate(proxy, opts.gateToken!);

    final useTls = (proxy["streamSettings"] as Map?)?["security"] is String &&
        ((proxy["streamSettings"] as Map)["security"] != "none");

    if (opts.fragment && useTls) {
      (proxy["streamSettings"] as Map<String, dynamic>)
          .putIfAbsent("sockopt", () => <String, dynamic>{})
          .cast<String, dynamic>()["dialerProxy"] = "fragment";
    }

    // No DoH servers = "plain through the tunnel": the core has no resolver of its own for
    // the phone's DNS, those queries are forwarded like any other traffic.
    final plainDns = opts.dohServers.isEmpty;

    final dnsServers = <dynamic>[
      // The proxy server's own hostname cannot be looked up *through* the proxy
      // (chicken-and-egg), so it alone uses the system resolver.
      if (host != null && !_isIp(host))
        {
          "address": "localhost",
          "domains": ["full:$host"],
        },
      if (plainDns) "1.1.1.1" else ...opts.dohServers,
    ];

    final config = <String, dynamic>{
      "log": {"loglevel": opts.logLevel},
      "stats": {},
      "policy": {
        "system": {"statsOutboundUplink": true, "statsOutboundDownlink": true},
      },
      "dns": {
        "servers": dnsServers,
        "queryStrategy": opts.ipv6 ? "UseIP" : "UseIPv4",
      },
      "inbounds": [
        {
          "tag": "tun-in",
          "protocol": "tun",
          "settings": {"name": "xray0", "mtu": opts.mtu},
          "sniffing": {
            "enabled": true,
            // The sniffed domain REPLACES the destination IP, so the proxy server resolves
            // the name itself (right CDN node, nothing depends on the client's DNS answer).
            // QUIC is blocked in routing, so it is not sniffed.
            "destOverride": ["http", "tls"],
            "routeOnly": false,
          },
        },
        if (opts.probe != null)
          {
            "tag": "probe-in",
            "listen": "127.0.0.1",
            "port": opts.probe!.port,
            "protocol": "http",
            "settings": {
              "accounts": [
                {"user": opts.probe!.user, "pass": opts.probe!.pass},
              ],
            },
          },
      ],
      "outbounds": [
        proxy,
        if (opts.fragment)
          {
            "tag": "fragment",
            "protocol": "freedom",
            "settings": {
              "fragment": {
                "packets": "tlshello",
                "length": "100-200",
                "interval": "10-20",
              },
            },
          },
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block", "protocol": "blackhole"},
        {"tag": "dns-out", "protocol": "dns"},
      ],
      "routing": {
        "domainStrategy": "AsIs",
        "rules": [
          // All DNS goes to Xray's resolver (DoH through the tunnel), unless plain DNS was chosen.
          if (!plainDns)
            {"type": "field", "port": "53", "outboundTag": "dns-out"},
          if (opts.blockQuic)
            {
              "type": "field",
              "network": "udp",
              "port": "443",
              "outboundTag": "block"
            },
          if (opts.bypassLan)
            {"type": "field", "ip": _lan, "outboundTag": "direct"},
          if (!opts.ipv6)
            {
              "type": "field",
              "ip": ["::/0"],
              "outboundTag": "block"
            },
        ],
      },
    };
    return config;
  }

  /// True when [link] sends its traffic to the server without TLS/Reality and without VLESS
  /// encryption (a plain `vless://…security=none`, or trojan without TLS): anyone on the path
  /// can read it. Such configs work, but the UI says so.
  static bool isUnencrypted(String link) {
    try {
      final l = link.trim();
      final scheme = l.split("://").first.toLowerCase();
      if (scheme != "vless" && scheme != "trojan") return false;
      final sec = (_outbound(l)["streamSettings"] as Map?)?["security"];
      if (sec == "tls" || sec == "reality") return false;
      if (scheme == "vless" &&
          (Uri.parse(l).queryParameters["encryption"] ?? "none") != "none") {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- gate ----------------------------------------------------------------

  /// Transports where the gate can check one header per connection. XHTTP in
  /// packet-up mode opens a request per packet, so it is not offered.
  static const _gateNetworks = {"ws", "httpupgrade"};

  /// True when [link] can sit behind the gate.
  static bool supportsGate(String link) {
    try {
      final net = (_outbound(link.trim())["streamSettings"] as Map)["network"];
      return _gateNetworks.contains(net);
    } on UnsupportedConfigException {
      return false;
    }
  }

  static void _applyGate(Map<String, dynamic> proxy, String token) {
    final ss = proxy["streamSettings"] as Map<String, dynamic>;
    final net = ss["network"];
    if (!_gateNetworks.contains(net)) {
      throw UnsupportedConfigException(
          "Gate needs a WebSocket or HTTPUpgrade transport (got '$net')");
    }
    final key = net == "ws" ? "wsSettings" : "httpupgradeSettings";
    final settings = Map<String, dynamic>.of(
        (ss[key] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{});
    settings["headers"] = {"X-Oversea-Auth": token};
    ss[key] = settings;
  }

  // ---- outbound ------------------------------------------------------------

  static Map<String, dynamic> _outbound(String link) {
    final scheme =
        link.contains("://") ? link.split("://").first.toLowerCase() : "";
    switch (scheme) {
      case "vless":
        return _vless(link);
      case "vmess":
        return _vmess(link);
      case "trojan":
        return _trojan(link);
      case "ss":
        return _shadowsocks(link);
      default:
        throw UnsupportedConfigException("Unsupported scheme: '$scheme'");
    }
  }

  static Map<String, dynamic> _vless(String link) {
    final u = Uri.parse(link);
    final q = u.queryParameters;
    if (u.userInfo.isEmpty || u.host.isEmpty || !u.hasPort) {
      throw const UnsupportedConfigException("Malformed vless link");
    }
    final enc = q["encryption"] ?? "none";
    return {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": u.host,
            "port": u.port,
            "users": [
              {
                "id": Uri.decodeComponent(u.userInfo),
                "encryption": enc,
                if ((q["flow"] ?? "").isNotEmpty) "flow": q["flow"],
              },
            ],
          },
        ],
      },
      "streamSettings": _stream(q),
    };
  }

  static Map<String, dynamic> _trojan(String link) {
    final u = Uri.parse(link);
    final q = u.queryParameters;
    if (u.userInfo.isEmpty || u.host.isEmpty || !u.hasPort) {
      throw const UnsupportedConfigException("Malformed trojan link");
    }
    // Trojan is TLS by default.
    final withDefault = {"security": "tls", ...q};
    return {
      "tag": "proxy",
      "protocol": "trojan",
      "settings": {
        "servers": [
          {
            "address": u.host,
            "port": u.port,
            "password": Uri.decodeComponent(u.userInfo),
          },
        ],
      },
      "streamSettings": _stream(withDefault),
    };
  }

  static Map<String, dynamic> _vmess(String link) {
    final body = link.substring("vmess://".length).split("#").first;
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(_b64(body))) as Map<String, dynamic>;
    } catch (_) {
      throw const UnsupportedConfigException("Malformed vmess link");
    }
    final port =
        j["port"] is int ? j["port"] as int : int.tryParse("${j["port"]}");
    final host = "${j["add"] ?? ""}";
    final id = "${j["id"] ?? ""}";
    if (host.isEmpty || port == null || id.isEmpty) {
      throw const UnsupportedConfigException("Malformed vmess link");
    }
    final tls = "${j["tls"] ?? ""}";
    final q = <String, String>{
      "type": "${j["net"] ?? "tcp"}",
      "security": tls == "tls" ? "tls" : "none",
      if ("${j["host"] ?? ""}".isNotEmpty) "host": "${j["host"]}",
      if ("${j["path"] ?? ""}".isNotEmpty) "path": "${j["path"]}",
      if ("${j["sni"] ?? ""}".isNotEmpty) "sni": "${j["sni"]}",
      if ("${j["alpn"] ?? ""}".isNotEmpty) "alpn": "${j["alpn"]}",
      if ("${j["fp"] ?? ""}".isNotEmpty) "fp": "${j["fp"]}",
      if ("${j["type"] ?? ""}".isNotEmpty) "headerType": "${j["type"]}",
      // vmess+grpc keeps the service name in "path".
      if ("${j["net"]}" == "grpc" && "${j["path"] ?? ""}".isNotEmpty)
        "serviceName": "${j["path"]}",
    };
    return {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": host,
            "port": port,
            "users": [
              {
                "id": id,
                "alterId": int.tryParse("${j["aid"] ?? 0}") ?? 0,
                "security": "${j["scy"] ?? "auto"}",
              },
            ],
          },
        ],
      },
      "streamSettings": _stream(q),
    };
  }

  static Map<String, dynamic> _shadowsocks(String link) {
    var body = link.substring("ss://".length);
    final hash = body.indexOf("#");
    if (hash >= 0) body = body.substring(0, hash);
    final qm = body.indexOf("?");
    if (qm >= 0) {
      final query = body.substring(qm + 1);
      body = body.substring(0, qm);
      if (query.contains("plugin=")) {
        throw const UnsupportedConfigException(
            "Shadowsocks plugins are not supported");
      }
    }
    body = body.replaceAll(RegExp(r"/+$"), "");

    String userinfo;
    String hostport;
    final at = body.lastIndexOf("@");
    try {
      if (at >= 0) {
        // SIP002: userinfo@host:port (userinfo base64url, or plain method:pass)
        final ui = body.substring(0, at);
        userinfo = ui.contains(":")
            ? Uri.decodeComponent(ui)
            : utf8.decode(_b64(Uri.decodeComponent(ui)));
        hostport = body.substring(at + 1);
      } else {
        // Legacy: base64(method:pass@host:port)
        final decoded = utf8.decode(_b64(body));
        final i = decoded.lastIndexOf("@");
        userinfo = decoded.substring(0, i);
        hostport = decoded.substring(i + 1);
      }
      final c = userinfo.indexOf(":");
      final method = userinfo.substring(0, c);
      final password = userinfo.substring(c + 1);
      final u = Uri.parse("ss://$hostport");
      if (u.host.isEmpty || !u.hasPort || method.isEmpty) {
        throw const FormatException();
      }
      return {
        "tag": "proxy",
        "protocol": "shadowsocks",
        "settings": {
          "servers": [
            {
              "address": u.host,
              "port": u.port,
              "method": method,
              "password": password,
            },
          ],
        },
        "streamSettings": {"network": "tcp"},
      };
    } on UnsupportedConfigException {
      rethrow;
    } catch (_) {
      throw const UnsupportedConfigException("Malformed shadowsocks link");
    }
  }

  // ---- transport + security -----------------------------------------------

  static Map<String, dynamic> _stream(Map<String, String> q) {
    final net = (q["type"] ?? "tcp").toLowerCase();
    final security = (q["security"] ?? "none").toLowerCase();
    final host = q["host"] ?? "";
    final path = q["path"] ?? "";

    final s = <String, dynamic>{};
    switch (net) {
      case "tcp":
        s["network"] = "tcp";
        if ((q["headerType"] ?? "none") == "http") {
          s["tcpSettings"] = {
            "header": {
              "type": "http",
              "request": {
                "path": [path.isEmpty ? "/" : path],
                if (host.isNotEmpty) "headers": {"Host": host.split(",")},
              },
            },
          };
        }
      case "ws":
        s["network"] = "ws";
        s["wsSettings"] = {
          if (path.isNotEmpty) "path": path,
          if (host.isNotEmpty) "host": host,
        };
      case "grpc":
        s["network"] = "grpc";
        s["grpcSettings"] = {
          "serviceName": q["serviceName"] ?? "",
          if (q["mode"] == "multi") "multiMode": true,
          if ((q["authority"] ?? "").isNotEmpty) "authority": q["authority"],
        };
      case "httpupgrade":
        s["network"] = "httpupgrade";
        s["httpupgradeSettings"] = {
          if (path.isNotEmpty) "path": path,
          if (host.isNotEmpty) "host": host,
        };
      case "xhttp":
      case "splithttp":
        s["network"] = "xhttp";
        s["xhttpSettings"] = {
          if (path.isNotEmpty) "path": path,
          if (host.isNotEmpty) "host": host,
          if ((q["mode"] ?? "").isNotEmpty) "mode": q["mode"],
        };
      default:
        throw UnsupportedConfigException("Unsupported transport: $net");
    }

    switch (security) {
      case "none":
        s["security"] = "none";
      case "tls":
        s["security"] = "tls";
        s["tlsSettings"] = {
          if ((q["sni"] ?? "").isNotEmpty)
            "serverName": q["sni"]
          else if (host.isNotEmpty)
            "serverName": host.split(",").first,
          "fingerprint": (q["fp"] ?? "").isNotEmpty ? q["fp"] : "chrome",
          if ((q["alpn"] ?? "").isNotEmpty) "alpn": q["alpn"]!.split(","),
          if ((q["ech"] ?? "").isNotEmpty) "echConfigList": q["ech"],
          if (q["allowInsecure"] == "1" || q["insecure"] == "1")
            "allowInsecure": true,
        };
      case "reality":
        if ((q["pbk"] ?? "").isEmpty) {
          throw const UnsupportedConfigException(
              "Reality link without public key (pbk)");
        }
        s["security"] = "reality";
        s["realitySettings"] = {
          "serverName": q["sni"] ?? "",
          "fingerprint": (q["fp"] ?? "").isNotEmpty ? q["fp"] : "chrome",
          "publicKey": q["pbk"],
          "shortId": q["sid"] ?? "",
          "spiderX": q["spx"] ?? "",
        };
      default:
        throw UnsupportedConfigException("Unsupported security: $security");
    }
    return s;
  }

  // ---- helpers -------------------------------------------------------------

  static String? _serverHost(Map<String, dynamic> proxy) {
    final st = proxy["settings"] as Map<String, dynamic>;
    final list = (st["vnext"] ?? st["servers"]) as List;
    return (list.first as Map<String, dynamic>)["address"] as String?;
  }

  static bool _isIp(String h) =>
      RegExp(r"^\d{1,3}(\.\d{1,3}){3}$").hasMatch(h) || h.contains(":");

  static List<int> _b64(String s) {
    final c = s.replaceAll("-", "+").replaceAll("_", "/").trim();
    final pad = (4 - c.length % 4) % 4;
    return base64.decode(c + "=" * pad);
  }
}
