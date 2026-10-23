import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/locked_config_codec.dart";
import "package:oversea/domain/tamper.dart";

const _cert =
    "9768438b82c322016e31a5b4ea216dab19f693d8d2613205a3dab896e42764c0";
const _play = "aa"
    "bb"
    "cc"
    "dd"
    "ee"
    "ff"
    "00"
    "11"
    "22"
    "33"
    "44"
    "55"
    "66"
    "77"
    "88"
    "99"
    "aa"
    "bb"
    "cc"
    "dd"
    "ee"
    "ff"
    "00"
    "11"
    "22"
    "33"
    "44"
    "55"
    "66"
    "77"
    "88"
    "99";

void main() {
  tearDown(() => LockedConfigCodec.environmentTag = "");

  group("Tamper.environmentTag", () {
    test("clean run => empty tag (identical to what the server computes)", () {
      expect(
          Tamper.environmentTag(cert: _cert, flags: 0, expected: {_cert}), "");
    });
    test("dev build without expected certs skips the signature check", () {
      expect(
          Tamper.environmentTag(cert: "anything", flags: 0, expected: {}), "");
      expect(Tamper.environmentTag(cert: null, flags: 0, expected: {}), "");
    });
    test("either accepted certificate passes (upload key or Play signing key)",
        () {
      expect(
          Tamper.environmentTag(
              cert: _play, flags: 0, expected: {_cert, _play}),
          "");
      expect(
          Tamper.environmentTag(
              cert: _cert.toUpperCase(), flags: 0, expected: {_cert, _play}),
          "");
    });
    test("re-signed (different certificate) is tainted", () {
      expect(Tamper.environmentTag(cert: "f" * 64, flags: 0, expected: {_cert}),
          isNotEmpty);
      expect(Tamper.environmentTag(cert: null, flags: 0, expected: {_cert}),
          isNotEmpty);
    });
    test("debugger, frida, xposed taint; the root hint alone does not", () {
      for (final f in [1, 2, 4, 3, 7]) {
        expect(Tamper.environmentTag(cert: _cert, flags: f, expected: {_cert}),
            isNotEmpty,
            reason: "flags $f");
      }
      expect(
          Tamper.environmentTag(cert: _cert, flags: 8, expected: {_cert}), "");
    });
    test("different problems give different tags", () {
      final a = Tamper.environmentTag(cert: _cert, flags: 1, expected: {_cert});
      final b = Tamper.environmentTag(cert: _cert, flags: 2, expected: {_cert});
      expect(a, isNot(b));
    });
    test("parseCerts accepts colon-separated and mixed case, drops junk", () {
      final colon = _cert
          .toUpperCase()
          .replaceAllMapped(RegExp(r".{2}"), (m) => "${m[0]}:")
          .replaceFirst(RegExp(r":$"), "");
      expect(Tamper.parseCerts("$colon, short ,$_play"), {_cert, _play});
      expect(Tamper.parseCerts(""), isEmpty);
    });
  });

  group("tag changes the key (no error message to patch out)", () {
    const cfg =
        "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls#T";

    test("a file made in a clean environment does not open in a tainted one",
        () async {
      final blob = await LockedConfigCodec.encode(cfg);
      expect((await LockedConfigCodec.decodeConfig(blob)).config, cfg);

      LockedConfigCodec.environmentTag = "tainted:f2";
      await expectLater(
          LockedConfigCodec.decodeConfig(blob), throwsA(anything));
    });

    test("and the reverse: files made while tainted are unreadable when clean",
        () async {
      LockedConfigCodec.environmentTag = "tainted:sig";
      final blob = await LockedConfigCodec.encode(cfg);
      LockedConfigCodec.environmentTag = "";
      await expectLater(
          LockedConfigCodec.decodeConfig(blob), throwsA(anything));
    });

    test("tainted environments fail the same way as a corrupt file", () async {
      final blob = await LockedConfigCodec.encode(cfg);
      LockedConfigCodec.environmentTag = "tainted:f1";
      Object? taint, corrupt;
      try {
        await LockedConfigCodec.decodeConfig(blob);
      } catch (e) {
        taint = e.runtimeType;
      }
      LockedConfigCodec.environmentTag = "";
      try {
        await LockedConfigCodec.decodeConfig("not-a-blob-at-all");
      } catch (e) {
        corrupt = e.runtimeType;
      }
      expect(taint, isNotNull);
      expect(corrupt, isNotNull);
    });

    test("gate token from a tainted environment differs from the clean one",
        () {
      final d = DateTime.utc(2026, 3, 3);
      final clean = GateToken.forKey(
          "app", "0123456789abcdef0123456789abcdef", "3FA9-0C21-B7D4-9E10", d);
      final tainted = GateToken.forKey(
          "app", "0123456789abcdef0123456789abcdef", "3FA9-0C21-B7D4-9E10", d,
          envTag: "tainted:f2");
      expect(tainted, isNot(clean));
      // clean tag leaves the token byte-identical to the server's computation
      expect(
          GateToken.forKey("app", "0123456789abcdef0123456789abcdef",
              "3FA9-0C21-B7D4-9E10", d,
              envTag: ""),
          clean);
    });

    test("signature still verifies for a clean file (sanity)", () async {
      final id = await CreatorIdentity.generate();
      final env = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(cfg, signer: id));
      expect(env.creator, id.fingerprint);
    });
  });
}
