import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/locked_config_codec.dart";

// Run with:
//   flutter test --dart-define=LOCK_P1=aaaaaaaaaaaaaaaa --dart-define=LOCK_P2=bbbbbbbbbbbbbbbb \
//                --dart-define=LOCK_P3=cccccccccccccccc --dart-define=LOCK_P4=dddddddddddddddd
void main() {
  signatureTests();
  const cfg =
      "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls#Test";

  test("round trip keeps config, ad and telegram", () async {
    final blob = await LockedConfigCodec.encode(cfg,
        adText: "join us", telegramUrl: "https://t.me/x");
    final env = await LockedConfigCodec.decodeConfig(blob);
    expect(env.config, cfg);
    expect(env.adText, "join us");
    expect(env.telegramUrl, "https://t.me/x");
  });

  test("looksLocked recognises blobs and rejects plain configs", () async {
    final blob = await LockedConfigCodec.encode(cfg);
    expect(LockedConfigCodec.looksLocked(blob), isTrue);
    expect(LockedConfigCodec.looksLocked(cfg), isFalse);
  });

  test("two locks of the same config differ (random salt/nonce)", () async {
    final a = await LockedConfigCodec.encode(cfg);
    final b = await LockedConfigCodec.encode(cfg);
    expect(a, isNot(b));
  });

  test("blob contains no cleartext config, host or ad", () async {
    final blob = await LockedConfigCodec.encode(cfg, adText: "SECRETAD");
    final raw = utf8.decode(
        base64Url.decode(blob + "=" * ((4 - blob.length % 4) % 4)),
        allowMalformed: true);
    expect(raw.contains("example.com"), isFalse);
    expect(raw.contains("vless"), isFalse);
    expect(raw.contains("SECRETAD"), isFalse);
  });

  test("any tampering is rejected", () async {
    final blob = await LockedConfigCodec.encode(cfg);
    final bytes = base64Url.decode(blob + "=" * ((4 - blob.length % 4) % 4));
    // flip a bit in header (salt), nonce, ciphertext and tag in turn
    for (final i in [8, 30, 40, bytes.length - 1]) {
      final t = List<int>.from(bytes)..[i] ^= 0x01;
      expect(() => LockedConfigCodec.decodeConfig(base64Url.encode(t)),
          throwsA(anything),
          reason: "byte $i");
    }
  });

  test("garbage and truncated input fail cleanly", () async {
    expect(
        () => LockedConfigCodec.decodeConfig("not-a-blob"), throwsA(anything));
    expect(() => LockedConfigCodec.decodeConfig(""), throwsA(anything));
  });
}

// ---- creator signatures ----------------------------------------------------
void signatureTests() {
  const cfg =
      "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls#T";

  group("creator signatures", () {
    test("signed file verifies and reports the creator's fingerprint",
        () async {
      final id = await CreatorIdentity.generate();
      final blob = await LockedConfigCodec.encode(cfg,
          adText: "hello", telegramUrl: "https://t.me/x", signer: id);
      final env = await LockedConfigCodec.decodeConfig(blob);
      expect(env.creator, id.fingerprint);
      expect(env.config, cfg);
    });

    test("unsigned file reports no creator", () async {
      final env = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(cfg));
      expect(env.creator, isNull);
    });

    test("two creators get different fingerprints", () async {
      final a = await CreatorIdentity.generate();
      final b = await CreatorIdentity.generate();
      expect(a.fingerprint, isNot(b.fingerprint));
      expect(a.fingerprint, matches(RegExp(r"^[0-9A-F]{4}(-[0-9A-F]{4}){3}$")));
    });

    test("same seed => same identity (survives restart)", () async {
      final a = await CreatorIdentity.generate();
      final b = await CreatorIdentity.fromSeed(a.seed);
      expect(b.fingerprint, a.fingerprint);
    });

    test(
        "re-branding: changing the ad and re-signing shows the copier's fingerprint",
        () async {
      final owner = await CreatorIdentity.generate();
      final copier = await CreatorIdentity.generate();
      final official = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(cfg, adText: "owner", signer: owner));
      // The copier opens the file (assume they extracted the secret) and re-locks it.
      final copy = await LockedConfigCodec.decodeConfig(
          await LockedConfigCodec.encode(official.config,
              adText: "copier", signer: copier));
      expect(official.creator, owner.fingerprint);
      expect(copy.creator, copier.fingerprint);
      expect(copy.creator, isNot(owner.fingerprint));
    });

    test("signature does not verify over a modified message or foreign key",
        () async {
      final id = await CreatorIdentity.generate();
      final other = await CreatorIdentity.generate();
      final sig = await id.sign([1, 2, 3]);
      expect(
          await CreatorIdentity.verify([1, 2, 3], sig, id.publicKey), isTrue);
      expect(
          await CreatorIdentity.verify([1, 2, 4], sig, id.publicKey), isFalse);
      expect(await CreatorIdentity.verify([1, 2, 3], sig, other.publicKey),
          isFalse);
      expect(
          await CreatorIdentity.verify([1, 2, 3], sig.sublist(1), id.publicKey),
          isFalse);
      expect(await CreatorIdentity.verify([1, 2, 3], sig, [1, 2]), isFalse);
    });
  });
}
