import "dart:convert";

/// An editable view of a share link (vless / vmess / trojan / shadowsocks). The editor form
/// reads one from a stored link ([ConfigDraft.fromLink]) or starts blank, and writes a link
/// back ([toLink]). Anything the form does not know about is kept in [extra] and written back,
/// so editing a config never silently drops a parameter.
enum DraftProtocol {
  vless("VLESS", "vless"),
  vmess("VMess", "vmess"),
  trojan("Trojan", "trojan"),
  shadowsocks("Shadowsocks", "ss");

  final String label;
  final String scheme;
  const DraftProtocol(this.label, this.scheme);
}

enum DraftNetwork {
  tcp("TCP"),
  ws("WebSocket"),
  httpupgrade("HTTPUpgrade"),
  grpc("gRPC"),
  xhttp("XHTTP");

  final String label;
  const DraftNetwork(this.label);
}

enum DraftSecurity {
  none("None"),
  tls("TLS"),
  reality("Reality");

  final String label;
  const DraftSecurity(this.label);
}

class ConfigDraft {
  DraftProtocol protocol;
  String name;
  String address;
  String port;

  /// UUID (vless / vmess) or password (trojan / shadowsocks).
  String secret;

  // vless
  String encryption;
  String flow;
  // vmess
  String vmessCipher;
  String alterId;
  // shadowsocks
  String ssMethod;

  // transport
  DraftNetwork network;
  String path;
  String hostHeader;
  String serviceName;
  String mode;
  String headerType;

  // security
  DraftSecurity security;
  String sni;
  String fingerprint;
  String alpn;
  String publicKey;
  String shortId;
  String spiderX;
  String pinnedCert;
  String verifyName;

  /// Query parameters / vmess keys this form has no field for.
  Map<String, String> extra;

  ConfigDraft({
    this.protocol = DraftProtocol.vless,
    this.name = "",
    this.address = "",
    this.port = "443",
    this.secret = "",
    this.encryption = "none",
    this.flow = "",
    this.vmessCipher = "auto",
    this.alterId = "0",
    this.ssMethod = "aes-256-gcm",
    this.network = DraftNetwork.tcp,
    this.path = "",
    this.hostHeader = "",
    this.serviceName = "",
    this.mode = "",
    this.headerType = "none",
    this.security = DraftSecurity.none,
    this.sni = "",
    this.fingerprint = "chrome",
    this.alpn = "",
    this.publicKey = "",
    this.shortId = "",
    this.spiderX = "",
    this.pinnedCert = "",
    this.verifyName = "",
    Map<String, String>? extra,
  }) : extra = extra ?? {};

  static const ssMethods = [
    "aes-256-gcm",
    "aes-128-gcm",
    "chacha20-ietf-poly1305",
    "2022-blake3-aes-128-gcm",
    "2022-blake3-aes-256-gcm",
    "2022-blake3-chacha20-poly1305",
  ];
  static const vmessCiphers = [
    "auto",
    "aes-128-gcm",
    "chacha20-poly1305",
    "none"
  ];
  static const fingerprints = [
    "chrome",
    "firefox",
    "safari",
    "ios",
    "android",
    "edge",
    "random",
    "randomized",
  ];

  /// A blank draft with sensible defaults for [p].
  factory ConfigDraft.blank(DraftProtocol p) {
    switch (p) {
      case DraftProtocol.vless:
        return ConfigDraft(protocol: p, security: DraftSecurity.tls);
      case DraftProtocol.vmess:
        return ConfigDraft(protocol: p, security: DraftSecurity.tls);
      case DraftProtocol.trojan:
        return ConfigDraft(protocol: p, security: DraftSecurity.tls);
      case DraftProtocol.shadowsocks:
        return ConfigDraft(protocol: p, port: "8388");
    }
  }

  // ---- parse -----------------------------------------------------------------

  /// Reads [link]; null when it is not one of the four editable protocols or is malformed.
  static ConfigDraft? fromLink(String link) {
    final l = link.trim();
    final scheme = l.contains("://") ? l.split("://").first.toLowerCase() : "";
    try {
      switch (scheme) {
        case "vless":
          return _fromUri(l, DraftProtocol.vless);
        case "trojan":
          return _fromUri(l, DraftProtocol.trojan);
        case "vmess":
          return _fromVmess(l);
        case "ss":
          return _fromSs(l);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _remark(String l) {
    final i = l.indexOf("#");
    if (i < 0 || i + 1 >= l.length) return "";
    try {
      return Uri.decodeComponent(l.substring(i + 1));
    } catch (_) {
      return l.substring(i + 1);
    }
  }

  static ConfigDraft _fromUri(String l, DraftProtocol p) {
    final u = Uri.parse(l);
    final q = Map<String, String>.of(u.queryParameters);
    String take(String k, [String d = ""]) => q.remove(k) ?? d;
    final d = ConfigDraft(
      protocol: p,
      name: _remark(l),
      address: u.host,
      port: u.hasPort ? "${u.port}" : "",
      secret: Uri.decodeComponent(u.userInfo),
    );
    if (p == DraftProtocol.vless) {
      d.encryption = take("encryption", "none");
      d.flow = take("flow");
    }
    d._readStream(q,
        defaultSecurity: p == DraftProtocol.trojan ? "tls" : "none");
    d.extra = q;
    return d;
  }

  void _readStream(Map<String, String> q, {required String defaultSecurity}) {
    String take(String k, [String d = ""]) => q.remove(k) ?? d;
    final net = take("type", "tcp").toLowerCase();
    network = DraftNetwork.values.firstWhere(
      (n) => n.name == (net == "splithttp" ? "xhttp" : net),
      orElse: () => DraftNetwork.tcp,
    );
    path = take("path");
    hostHeader = take("host");
    serviceName = take("serviceName");
    mode = take("mode");
    headerType = take("headerType", "none");
    final sec = take("security", defaultSecurity).toLowerCase();
    security = DraftSecurity.values
        .firstWhere((s) => s.name == sec, orElse: () => DraftSecurity.none);
    sni = take("sni");
    fingerprint = take("fp", "chrome");
    alpn = take("alpn");
    publicKey = take("pbk");
    shortId = take("sid");
    spiderX = take("spx");
    pinnedCert = take("pcs");
    verifyName = take("vcn");
  }

  static ConfigDraft _fromVmess(String l) {
    final body = l.substring("vmess://".length).split("#").first;
    final j = jsonDecode(utf8.decode(_b64(body))) as Map<String, dynamic>;
    String s(String k, [String d = ""]) {
      final v = j.remove(k);
      return v == null ? d : "$v";
    }

    final d = ConfigDraft(protocol: DraftProtocol.vmess);
    d.name = s("ps");
    d.address = s("add");
    d.port = s("port");
    d.secret = s("id");
    d.alterId = s("aid", "0");
    d.vmessCipher = s("scy", "auto");
    final net = s("net", "tcp").toLowerCase();
    d.network = DraftNetwork.values
        .firstWhere((n) => n.name == net, orElse: () => DraftNetwork.tcp);
    d.hostHeader = s("host");
    final p = s("path");
    if (d.network == DraftNetwork.grpc) {
      d.serviceName = p;
    } else {
      d.path = p;
    }
    d.headerType = s("type", "none");
    d.security = s("tls") == "tls" ? DraftSecurity.tls : DraftSecurity.none;
    d.sni = s("sni");
    d.alpn = s("alpn");
    d.fingerprint = s("fp", "chrome");
    j.remove("v");
    d.extra = {for (final e in j.entries) e.key: "${e.value}"};
    return d;
  }

  static ConfigDraft _fromSs(String l) {
    var body = l.substring("ss://".length);
    final name = _remark(l);
    final hash = body.indexOf("#");
    if (hash >= 0) body = body.substring(0, hash);
    final qm = body.indexOf("?");
    if (qm >= 0) body = body.substring(0, qm);
    body = body.replaceAll(RegExp(r"/+$"), "");
    String userinfo, hostport;
    final at = body.lastIndexOf("@");
    if (at >= 0) {
      final ui = body.substring(0, at);
      userinfo = ui.contains(":")
          ? Uri.decodeComponent(ui)
          : utf8.decode(_b64(Uri.decodeComponent(ui)));
      hostport = body.substring(at + 1);
    } else {
      final decoded = utf8.decode(_b64(body));
      final i = decoded.lastIndexOf("@");
      userinfo = decoded.substring(0, i);
      hostport = decoded.substring(i + 1);
    }
    final c = userinfo.indexOf(":");
    final u = Uri.parse("ss://$hostport");
    return ConfigDraft(
      protocol: DraftProtocol.shadowsocks,
      name: name,
      address: u.host,
      port: u.hasPort ? "${u.port}" : "",
      ssMethod: userinfo.substring(0, c),
      secret: userinfo.substring(c + 1),
    );
  }

  static List<int> _b64(String s) {
    var t = s
        .replaceAll("-", "+")
        .replaceAll("_", "/")
        .replaceAll(RegExp(r"\s"), "");
    while (t.length % 4 != 0) {
      t += "=";
    }
    return base64.decode(t);
  }

  // ---- validate --------------------------------------------------------------

  static final _uuid = RegExp(
      r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

  /// Field errors by field key; empty when [toLink] will produce a usable link.
  Map<String, String> errors() {
    final e = <String, String>{};
    if (address.trim().isEmpty) e["address"] = "Enter the server address";
    final p = int.tryParse(port.trim());
    if (p == null || p < 1 || p > 65535) e["port"] = "Port must be 1–65535";
    if (secret.trim().isEmpty) {
      e["secret"] =
          protocol == DraftProtocol.vless || protocol == DraftProtocol.vmess
              ? "Enter the user ID (UUID)"
              : "Enter the password";
    } else if ((protocol == DraftProtocol.vless ||
            protocol == DraftProtocol.vmess) &&
        !_uuid.hasMatch(secret.trim())) {
      e["secret"] = "That is not a valid UUID";
    }
    if (protocol == DraftProtocol.vmess) {
      final a = int.tryParse(alterId.trim());
      if (a == null || a < 0) e["alterId"] = "Alter ID must be 0 or more";
    }
    if (security == DraftSecurity.reality && publicKey.trim().isEmpty) {
      e["publicKey"] = "Reality needs the server's public key";
    }
    if (network == DraftNetwork.grpc &&
        serviceName.trim().isEmpty &&
        protocol != DraftProtocol.shadowsocks) {
      e["serviceName"] = "gRPC needs a service name";
    }
    return e;
  }

  // ---- write -----------------------------------------------------------------

  /// The share link. Call only when [errors] is empty.
  String toLink() {
    switch (protocol) {
      case DraftProtocol.vmess:
        return _vmessLink();
      case DraftProtocol.shadowsocks:
        return _ssLink();
      case DraftProtocol.vless:
      case DraftProtocol.trojan:
        return _uriLink();
    }
  }

  String get _remarkFragment {
    final n = name.trim().isEmpty ? address.trim() : name.trim();
    return "#${Uri.encodeComponent(n)}";
  }

  String _uriLink() {
    final q = <String, String>{};
    void put(String k, String v) {
      if (v.trim().isNotEmpty) q[k] = v.trim();
    }

    if (protocol == DraftProtocol.vless) {
      q["encryption"] = encryption.trim().isEmpty ? "none" : encryption.trim();
      put("flow", flow);
    }
    q["security"] = security.name;
    q["type"] = network.name;
    if (network != DraftNetwork.tcp && network != DraftNetwork.grpc) {
      put("path", path);
      put("host", hostHeader);
    }
    if (network == DraftNetwork.tcp && headerType == "http") {
      q["headerType"] = "http";
      put("path", path);
      put("host", hostHeader);
    }
    if (network == DraftNetwork.grpc) {
      put("serviceName", serviceName);
      put("mode", mode);
    }
    if (network == DraftNetwork.xhttp) put("mode", mode);
    if (security != DraftSecurity.none) {
      put("sni", sni);
      put("fp", fingerprint);
    }
    if (security == DraftSecurity.tls) {
      put("alpn", alpn);
      put("pcs", pinnedCert);
      put("vcn", verifyName);
    }
    if (security == DraftSecurity.reality) {
      put("pbk", publicKey);
      put("sid", shortId);
      put("spx", spiderX);
    }
    for (final e in extra.entries) {
      q.putIfAbsent(e.key, () => e.value);
    }
    final query = q.entries
        .map((e) =>
            "${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}")
        .join("&");
    final user = Uri.encodeComponent(secret.trim());
    return "${protocol.scheme}://$user@${_hostForUri(address.trim())}:${port.trim()}"
        "${query.isEmpty ? "" : "?$query"}$_remarkFragment";
  }

  static String _hostForUri(String h) =>
      h.contains(":") && !h.startsWith("[") ? "[$h]" : h;

  String _vmessLink() {
    final j = <String, dynamic>{
      "v": "2",
      "ps": name.trim().isEmpty ? address.trim() : name.trim(),
      "add": address.trim(),
      "port": port.trim(),
      "id": secret.trim(),
      "aid": alterId.trim().isEmpty ? "0" : alterId.trim(),
      "scy": vmessCipher,
      "net": network.name,
      "type": headerType.isEmpty ? "none" : headerType,
      "host": hostHeader.trim(),
      "path": network == DraftNetwork.grpc ? serviceName.trim() : path.trim(),
      "tls": security == DraftSecurity.tls ? "tls" : "",
      "sni": security == DraftSecurity.tls ? sni.trim() : "",
      "alpn": security == DraftSecurity.tls ? alpn.trim() : "",
      "fp": security == DraftSecurity.tls ? fingerprint : "",
    };
    for (final e in extra.entries) {
      j.putIfAbsent(e.key, () => e.value);
    }
    return "vmess://${base64.encode(utf8.encode(jsonEncode(j)))}";
  }

  String _ssLink() {
    final ui = base64Url
        .encode(utf8.encode("$ssMethod:${secret.trim()}"))
        .replaceAll("=", "");
    return "ss://$ui@${_hostForUri(address.trim())}:${port.trim()}$_remarkFragment";
  }
}
