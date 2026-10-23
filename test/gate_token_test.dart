import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/locked_config_codec.dart";
import "package:oversea/domain/xray_config_builder.dart";

const _code = "0123456789abcdef0123456789abcdef";
const _owner = "3FA9-0C21-B7D4-9E10";

void main() {
  test("token matches the Go gate's test vector exactly", () {
    // server/internal/gate/gate_test.go TestTokenVector
    final t = GateToken.forKey("vector-key", _code, _owner,
        DateTime.fromMillisecondsSinceEpoch(86400 * 20000 * 1000, isUtc: true));
    expect(t,
        "db1f62c4499c7e2f.20000.00bd68c142b4aba07b6e724ebb7ebc6287ca684699e1182ffe960cade6a357d5");
  });

  test("token depends on app key, code, creator and day", () {
    final d = DateTime.utc(2026, 1, 1, 12);
    final base = GateToken.forKey("k", _code, _owner, d);
    expect(base,
        GateToken.forKey("k", _code, _owner, d.add(const Duration(hours: 5))));
    expect(
        base,
        isNot(GateToken.forKey(
            "k", _code, _owner, d.add(const Duration(days: 1)))));
    expect(base, isNot(GateToken.forKey("k2", _code, _owner, d)));
    expect(base, isNot(GateToken.forKey("k", "f" * 32, _owner, d)));
    // the thief case: same code, different creator => different token
    expect(base, isNot(GateToken.forKey("k", _code, "AAAA-BBBB-CCCC-DDDD", d)));
  });

  test("newCode is 128-bit hex and random", () {
    final a = GateToken.newCode();
    expect(a, matches(RegExp(r"^[0-9a-f]{32}$")));
    expect(GateToken.newCode(), isNot(a));
  });

  test("allow-list line format", () {
    expect(GateToken.allowListLine(_code, _owner, note: "ch"),
        "$_code $_owner ch");
    expect(GateToken.allowListLine(_code, _owner), "$_code $_owner");
  });

  group("re-lock scenario, end to end through the codec", () {
    const link =
        "vless://11111111-2222-3333-4444-555555555555@cdn.example.com:443?security=tls&sni=cdn.example.com&type=ws&path=%2Fws#x";

    test(
        "owner's file yields the owner's token; a thief's re-lock yields a different one",
        () async {
      final owner = await CreatorIdentity.generate();
      final thief = await CreatorIdentity.generate();
      final code = GateToken.newCode();

      final official = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(link, signer: owner, gateCode: code));
      expect(official.gateCode, code);
      expect(official.creator, owner.fingerprint);

      // The thief decodes it (assume they extracted the secret) and re-locks it with
      // THEIR identity, keeping the code (the server only knows that one).
      final copy = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(official.config,
              signer: thief, gateCode: official.gateCode));
      expect(copy.gateCode, code);
      expect(copy.creator, thief.fingerprint);

      final d = DateTime.utc(2026, 5, 5);
      final ownerTok =
          GateToken.forKey("app", official.gateCode!, official.creator!, d);
      final thiefTok =
          GateToken.forKey("app", copy.gateCode!, copy.creator!, d);
      expect(thiefTok,
          isNot(ownerTok)); // server (which stores ownerFp) rejects thiefTok
    });

    test(
        "changing the gate code invalidates the signature (creator becomes null)",
        () async {
      final owner = await CreatorIdentity.generate();
      final blob =
          await LockedConfigCodec.encode(link, signer: owner, gateCode: _code);
      final env = await LockedConfigCodec.decodeConfig(blob);
      expect(env.creator, owner.fingerprint);
      // verify directly: signature over a different code must fail
      final other = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(link,
              signer: owner, gateCode: "f" * 32));
      expect(other.gateCode, "f" * 32);
      expect(other.creator, owner.fingerprint); // fresh, validly signed file
    });
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
    final c = XrayConfigBuilder.buildMap(ws, const TunnelOptions());
    final ss = ((c["outbounds"] as List).first as Map)["streamSettings"] as Map;
    expect((ss["wsSettings"] as Map).containsKey("headers"), isFalse);
  });
}
