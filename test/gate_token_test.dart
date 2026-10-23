import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/xray_config_builder.dart";

void main() {
  test("token matches the Go gate's test vector exactly", () {
    // server/internal/gate/gate_test.go TestTokenVector
    final t = GateToken.forKey("vector-key",
        DateTime.fromMillisecondsSinceEpoch(86400 * 20000 * 1000, isUtc: true));
    expect(t,
        "20000.b323d70d7f74fe7b5643d0abe27153bb5ecfb4e931781f6797ac71860cea7d07");
  });

  test("token changes daily and with the key", () {
    final d = DateTime.utc(2026, 1, 1, 12);
    expect(GateToken.forKey("k", d),
        GateToken.forKey("k", d.add(const Duration(hours: 5))));
    expect(GateToken.forKey("k", d),
        isNot(GateToken.forKey("k", d.add(const Duration(days: 1)))));
    expect(GateToken.forKey("k", d), isNot(GateToken.forKey("k2", d)));
  });

  const ws =
      "vless://11111111-2222-3333-4444-555555555555@cdn.example.com:443?security=tls&sni=cdn.example.com&type=ws&path=%2Fws#x";
  const hu =
      "vless://11111111-2222-3333-4444-555555555555@cdn.example.com:443?security=tls&sni=cdn.example.com&type=httpupgrade&path=%2Fh#x";
  const tcp =
      "vless://11111111-2222-3333-4444-555555555555@h.com:443?security=tls&sni=h.com&type=tcp#x";
  const xhttp =
      "vless://11111111-2222-3333-4444-555555555555@h.com:443?security=tls&sni=h.com&type=xhttp&path=%2Fx#x";

  Map<String, dynamic> streamOf(String link) {
    final c = XrayConfigBuilder.buildMap(
        link, const TunnelOptions(gateToken: "TOKEN"));
    return ((c["outbounds"] as List).first as Map)["streamSettings"]
        as Map<String, dynamic>;
  }

  test("gate token goes into ws and httpupgrade headers", () {
    expect((streamOf(ws)["wsSettings"] as Map)["headers"],
        {"X-Oversea-Auth": "TOKEN"});
    expect((streamOf(hu)["httpupgradeSettings"] as Map)["headers"],
        {"X-Oversea-Auth": "TOKEN"});
    // other ws settings survive
    expect((streamOf(ws)["wsSettings"] as Map)["path"], "/ws");
  });

  test("transports that cannot be gated are refused, not silently ungated", () {
    expect(XrayConfigBuilder.supportsGate(ws), isTrue);
    expect(XrayConfigBuilder.supportsGate(hu), isTrue);
    expect(XrayConfigBuilder.supportsGate(tcp), isFalse);
    expect(XrayConfigBuilder.supportsGate(xhttp), isFalse);
    expect(XrayConfigBuilder.supportsGate("nonsense"), isFalse);
    for (final l in [tcp, xhttp]) {
      expect(
          () => XrayConfigBuilder.build(l, const TunnelOptions(gateToken: "T")),
          throwsA(isA<UnsupportedConfigException>()));
    }
  });

  test("no token => no header", () {
    expect((streamOf(ws)["wsSettings"] as Map).containsKey("headers"), isTrue);
    final c = XrayConfigBuilder.buildMap(ws, const TunnelOptions());
    final ss = ((c["outbounds"] as List).first as Map)["streamSettings"] as Map;
    expect((ss["wsSettings"] as Map).containsKey("headers"), isFalse);
  });
}
