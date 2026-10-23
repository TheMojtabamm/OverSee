import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/locked_config_codec.dart";

// Run with:
//   flutter test --dart-define=LOCK_P1=aaaaaaaaaaaaaaaa --dart-define=LOCK_P2=bbbbbbbbbbbbbbbb \
//                --dart-define=LOCK_P3=cccccccccccccccc --dart-define=LOCK_P4=dddddddddddddddd
void main() {
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
