import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/config_draft.dart";
import "package:oversea/domain/xray_config_builder.dart";

Map<String, dynamic> _cfg(String link) =>
    jsonDecode(XrayConfigBuilder.build(link, const TunnelOptions()))
        as Map<String, dynamic>;

void main() {
  final links = File("test/fixtures/xray_links.txt")
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty && !l.startsWith("#"))
      .toList();

  test("editing and saving without changes keeps the Xray config identical",
      () {
    var checked = 0;
    for (final link in links) {
      final d = ConfigDraft.fromLink(link);
      if (d == null) continue; // not one of the four editable protocols
      expect(d.errors(), isEmpty, reason: link);
      final back = d.toLink();
      expect(_cfg(back), _cfg(link), reason: "round trip changed: $link");
      checked++;
    }
    expect(checked, greaterThan(5));
  });

  test("a second round trip is stable", () {
    for (final link in links) {
      final d = ConfigDraft.fromLink(link);
      if (d == null) continue;
      final once = d.toLink();
      expect(ConfigDraft.fromLink(once)!.toLink(), once, reason: link);
    }
  });

  test("unknown parameters survive an edit", () {
    final d = ConfigDraft.fromLink(
        "vless://11111111-2222-3333-4444-555555555555@a.example.com:443?encryption=none&security=tls&sni=a.example.com&type=ws&path=%2Fx&ech=ABC&weird=1#n")!;
    d.name = "renamed";
    final back = d.toLink();
    expect(back, contains("weird=1"));
    expect(back, contains("ech=ABC"));
    expect(back, endsWith("#renamed"));
  });

  test("blank drafts need an address, a port and a secret", () {
    final d = ConfigDraft.blank(DraftProtocol.vless);
    expect(d.errors().keys, containsAll(["address", "secret"]));
    d.address = "example.com";
    d.secret = "not-a-uuid";
    expect(d.errors()["secret"], contains("UUID"));
    d.secret = "11111111-2222-3333-4444-555555555555";
    d.port = "70000";
    expect(d.errors()["port"], isNotNull);
    d.port = "443";
    expect(d.errors(), isEmpty);
  });

  test("a hand-made config of every protocol builds a loadable Xray config",
      () {
    const uuid = "11111111-2222-3333-4444-555555555555";
    for (final p in DraftProtocol.values) {
      final d = ConfigDraft.blank(p)
        ..name = "manual ${p.label}"
        ..address = "server.example.com"
        ..secret = p == DraftProtocol.vless || p == DraftProtocol.vmess
            ? uuid
            : "s3cret-pass";
      expect(d.errors(), isEmpty, reason: p.name);
      final link = d.toLink();
      expect(() => XrayConfigBuilder.build(link, const TunnelOptions()),
          returnsNormally,
          reason: p.name);
      expect(ConfigDraft.fromLink(link)!.address, "server.example.com");
    }
  });

  test("ws + tls + reality fields land in the right place", () {
    final d = ConfigDraft.blank(DraftProtocol.vless)
      ..address = "h.example.com"
      ..secret = "11111111-2222-3333-4444-555555555555"
      ..network = DraftNetwork.ws
      ..path = "/a b"
      ..hostHeader = "cdn.example.com"
      ..security = DraftSecurity.reality
      ..sni = "www.example.com"
      ..publicKey = "PBK"
      ..shortId = "ab12";
    final c = _cfg(d.toLink());
    final ss = (c["outbounds"] as List).first["streamSettings"] as Map;
    expect(ss["network"], "ws");
    expect(ss["wsSettings"]["path"], "/a b");
    expect(ss["wsSettings"]["host"], "cdn.example.com");
    expect(ss["security"], "reality");
    expect(ss["realitySettings"]["publicKey"], "PBK");
  });
}
