import "dart:io";
import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/locked_config_codec.dart";
import "package:oversea/domain/native_core.dart";

// Needs a host build of the native core compiled with the same dev secrets the Dart
// side is given (see tool/build_native_host.sh). Skipped when it isn't available, so
// a plain `flutter test` keeps working.
final _lib = Platform.environment["OVS_NATIVE_LIB"];

void main() {
  final skip = (_lib == null || _lib!.isEmpty)
      ? "set OVS_NATIVE_LIB (tool/build_native_host.sh builds it)"
      : false;

  tearDown(() {
    LockedConfigCodec.preferNative = true;
    LockedConfigCodec.environmentTag = "";
  });

  const cfg =
      "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls#T";

  test("the library loads and reports both keys", () {
    final n = NativeCore.instance;
    expect(n, isNotNull);
    expect(n!.hasLockKey, isTrue);
    expect(n.hasGateKey, isTrue);
  }, skip: skip);

  test(
      "native file key == Dart file key, for random salts, generations and env tags",
      () async {
    final n = NativeCore.instance!;
    final r = Random(7);
    for (var i = 0; i < 12; i++) {
      final salt = List<int>.generate(16, (_) => r.nextInt(256));
      final tag = i.isEven ? "" : "tainted:f${i % 7}";
      LockedConfigCodec.environmentTag = tag;
      final nativeKey =
          n.deriveFileKey(LockedConfigCodec.keyGeneration, salt, tag)!;

      // Encrypt natively, decrypt with the pure-Dart path (and the reverse): the two
      // implementations must agree byte for byte or one of these fails.
      LockedConfigCodec.preferNative = true;
      final blob = await LockedConfigCodec.encode(cfg, adText: "ad $i");
      LockedConfigCodec.preferNative = false;
      final viaDart = await LockedConfigCodec.decodeConfig(blob);
      expect(viaDart.config, cfg,
          reason: "native-encrypted must open in Dart (tag '$tag')");

      final blob2 = await LockedConfigCodec.encode(cfg);
      LockedConfigCodec.preferNative = true;
      expect((await LockedConfigCodec.decodeConfig(blob2)).config, cfg,
          reason: "Dart-encrypted must open natively (tag '$tag')");
      expect(nativeKey.length, 32);
    }
  }, skip: skip);

  test(
      "the native library produces the same gate token as the Dart/Go construction",
      () {
    final n = NativeCore.instance!;
    const code = "0123456789abcdef0123456789abcdef";
    const fp = "3FA9-0C21-B7D4-9E10";
    final day = DateTime.utc(2026, 5, 5).millisecondsSinceEpoch ~/ 86400000;
    final dartTok =
        GateToken.forKey("gate-dev-key", code, fp, DateTime.utc(2026, 5, 5));
    expect(dartTok,
        "${GateToken.codeId(code)}.$day.${n.gateMac(code, fp, day, "")}");
    // and an env tag changes it the same way on both sides
    final taintedDart = GateToken.forKey(
        "gate-dev-key", code, fp, DateTime.utc(2026, 5, 5),
        envTag: "tainted:sig");
    expect(
        taintedDart.split(".").last, n.gateMac(code, fp, day, "tainted:sig"));
  }, skip: skip);

  test("signed, gated, expiring file round-trips natively", () async {
    final id = await CreatorIdentity.generate();
    final blob = await LockedConfigCodec.encode(cfg,
        signer: id,
        gateCode: GateToken.newCode(),
        expiresAt: DateTime.now().add(const Duration(days: 1)));
    final env = await LockedConfigCodec.decodeConfig(blob);
    expect(env.creator, id.fingerprint);
    expect(env.gateCode, isNotNull);
    expect(env.isExpired(), isFalse);
  }, skip: skip);
}
