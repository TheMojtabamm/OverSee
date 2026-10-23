import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/xray_config_builder.dart";

Map<String, dynamic> build(String link,
        [TunnelOptions o = const TunnelOptions()]) =>
    jsonDecode(XrayConfigBuilder.build(link, o)) as Map<String, dynamic>;

Map<String, dynamic> proxyOf(Map<String, dynamic> c) =>
    (c["outbounds"] as List).first as Map<String, dynamic>;

List<dynamic> rules(Map<String, dynamic> c) =>
    (c["routing"] as Map)["rules"] as List;

const vless =
    "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls&sni=example.com&type=tcp#x";

void main() {
  final links = File("test/fixtures/xray_links.txt")
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  test("every fixture link builds under every option set", () {
    for (final l in links) {
      for (final o in const [
        TunnelOptions(),
        TunnelOptions(fragment: true),
        TunnelOptions(dohServers: []),
        TunnelOptions(ipv6: true, bypassLan: false),
      ]) {
        expect(() => XrayConfigBuilder.build(l, o), returnsNormally, reason: l);
      }
    }
  });

  test("traffic enters through the tun inbound and all DNS goes to dns-out",
      () {
    final c = build(vless);
    final inbound = (c["inbounds"] as List).single as Map;
    expect(inbound["protocol"], "tun");
    expect(rules(c).first,
        {"type": "field", "port": "53", "outboundTag": "dns-out"});
  });

  test(
      "IPv6 is dropped in the tunnel by default (no leak) and kept when enabled",
      () {
    bool dropsV6(Map<String, dynamic> c) => rules(c).any((r) =>
        (r as Map)["outboundTag"] == "block" &&
        ((r["ip"] as List?)?.contains("::/0") ?? false));
    expect(dropsV6(build(vless)), isTrue);
    expect(dropsV6(build(vless, const TunnelOptions(ipv6: true))), isFalse);
  });

  test("LAN bypass is optional", () {
    bool hasDirect(Map<String, dynamic> c) =>
        rules(c).any((r) => (r as Map)["outboundTag"] == "direct");
    expect(hasDirect(build(vless)), isTrue);
    expect(hasDirect(build(vless, const TunnelOptions(bypassLan: false))),
        isFalse);
  });

  test("fragment adds a freedom outbound and points the proxy at it", () {
    final c = build(vless, const TunnelOptions(fragment: true));
    final ss = proxyOf(c)["streamSettings"] as Map;
    expect((ss["sockopt"] as Map)["dialerProxy"], "fragment");
    expect((c["outbounds"] as List).any((o) => (o as Map)["tag"] == "fragment"),
        isTrue);
    expect(
        ((proxyOf(build(vless))["streamSettings"]) as Map)
            .containsKey("sockopt"),
        isFalse);
  });

  test("the proxy hostname is resolved locally, never through the proxy", () {
    final servers = (build(vless)["dns"] as Map)["servers"] as List;
    expect((servers.first as Map)["domains"], ["full:example.com"]);
    // An IP-literal server needs no special case.
    final ipLink = vless.replaceFirst("example.com:443", "1.2.3.4:443");
    expect(((build(ipLink)["dns"] as Map)["servers"] as List).first,
        isA<String>());
  });

  test("reality maps public key / short id / flow", () {
    final c = build(
        "vless://11111111-2222-3333-4444-555555555555@h.com:443?security=reality&sni=www.google.com&pbk=${'A' * 43}&sid=ab12&fp=firefox&flow=xtls-rprx-vision&type=tcp");
    final p = proxyOf(c);
    final rs = (p["streamSettings"] as Map)["realitySettings"] as Map;
    expect(rs["publicKey"], 'A' * 43);
    expect(rs["shortId"], "ab12");
    expect(rs["fingerprint"], "firefox");
    final user =
        (((p["settings"] as Map)["vnext"] as List).first["users"] as List)
            .first;
    expect(user["flow"], "xtls-rprx-vision");
  });

  test("shadowsocks: SIP002 and legacy forms agree on the credentials", () {
    final sip = build(links.firstWhere((l) => l.contains("ss-sip002")));
    final legacy = build(links.firstWhere((l) => l.contains("ss-legacy")));
    final a =
        ((proxyOf(sip)["settings"] as Map)["servers"] as List).first as Map;
    final b =
        ((proxyOf(legacy)["settings"] as Map)["servers"] as List).first as Map;
    expect(a["method"], "aes-256-gcm");
    expect(a["password"], "secretpass");
    expect(b["method"], "chacha20-ietf-poly1305");
    expect(b["address"], "ss.example.com");
    expect(b["port"], 443);
  });

  test("garbage and unsupported inputs throw a clean exception", () {
    for (final bad in [
      "",
      "hello",
      "http://example.com",
      "hysteria2://a@h:1",
      "vless://@h:1",
      "vless://u@h",
      "vmess://not-base64!!",
      "ss://%%%",
      "ss://YWVzLTI1Ni1nY206cHc=@h:1?plugin=obfs-local",
      "vless://11111111-2222-3333-4444-555555555555@h.com:443?security=reality&sni=x",
      "vless://11111111-2222-3333-4444-555555555555@h.com:443?type=quic&security=tls",
      "vless://11111111-2222-3333-4444-555555555555@h.com:443?type=tcp&security=weird",
    ]) {
      expect(() => XrayConfigBuilder.build(bad),
          throwsA(isA<UnsupportedConfigException>()),
          reason: bad);
    }
  });

  test("passwords with special characters survive", () {
    final c =
        build(links.firstWhere((l) => l.startsWith("trojan://pa%24%24word")));
    final s = ((proxyOf(c)["settings"] as Map)["servers"] as List).first as Map;
    expect(s["password"], r"pa$$word");
  });

  test("the probe proxy is loopback-only, password-protected and optional", () {
    const link =
        "vless://11111111-2222-3333-4444-555555555555@h.example.com:443"
        "?security=tls&sni=h.example.com&type=ws&path=%2Fws#x";
    final without = XrayConfigBuilder.buildMap(link, const TunnelOptions());
    expect((without["inbounds"] as List).length, 1);
    final withProbe = XrayConfigBuilder.buildMap(
        link, const TunnelOptions(probe: ProbeEndpoint(24680, "u", "p")));
    final inbounds =
        (withProbe["inbounds"] as List).cast<Map<String, dynamic>>();
    final probe = inbounds.firstWhere((i) => i["tag"] == "probe-in");
    expect(probe["listen"], "127.0.0.1");
    expect(probe["port"], 24680);
    expect(probe["protocol"], "http");
    expect(
        ((probe["settings"] as Map<String, dynamic>)["accounts"] as List)
            .single,
        {"user": "u", "pass": "p"});
  });

  test("plain DNS: no resolver rule, DNS queries travel through the proxy", () {
    final c =
        XrayConfigBuilder.buildMap(vless, const TunnelOptions(dohServers: []));
    expect(
        rules(c).where((r) => (r as Map)["outboundTag"] == "dns-out"), isEmpty);
    expect((c["dns"] as Map<String, dynamic>)["servers"], contains("1.1.1.1"));
    // DoH mode keeps the rule
    expect((rules(build(vless)).first as Map)["outboundTag"], "dns-out");
  });

  test("QUIC (udp/443) is blocked by default so apps fall back to TCP", () {
    bool quic(Map<String, dynamic> c) => rules(c).any((r) =>
        (r as Map)["network"] == "udp" &&
        r["port"] == "443" &&
        r["outboundTag"] == "block");
    expect(quic(build(vless)), isTrue);
    expect(
        quic(XrayConfigBuilder.buildMap(
            vless, const TunnelOptions(blockQuic: false))),
        isFalse);
  });
}
