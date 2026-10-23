import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/secret_mask.dart";

void main() {
  const secret = "s3cr3t-Value_ünï/ok-0123456789";
  const mask = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718";

  test("mask then unmask returns the original, for every index", () {
    for (var i = 0; i < 5; i++) {
      expect(
          SecretMask.unmask(SecretMask.mask(secret, mask, i), mask, i), secret);
    }
  });

  test("the embedded value does not contain the secret and is hex", () {
    final m = SecretMask.mask(secret, mask, 0);
    expect(m.contains("s3cr3t"), isFalse);
    expect(m, matches(RegExp(r"^[0-9a-f]+$")));
  });

  test(
      "a different mask (every build) gives different bytes; same secret recovered",
      () {
    const mask2 = "00112233445566778899aabbccddeeff0011223344556677";
    final a = SecretMask.mask(secret, mask, 1);
    final b = SecretMask.mask(secret, mask2, 1);
    expect(a, isNot(b));
    expect(SecretMask.unmask(b, mask2, 1), secret);
  });

  test("equal secrets at different indexes mask to different bytes", () {
    expect(SecretMask.mask("same-value", mask, 0),
        isNot(SecretMask.mask("same-value", mask, 1)));
  });

  test("no mask (dev/test builds) leaves the value untouched", () {
    expect(SecretMask.unmask("plain-dev-value", "", 0), "plain-dev-value");
    expect(SecretMask.unmask("", mask, 0), "");
  });

  test("wrong mask does not recover the secret", () {
    final m = SecretMask.mask(secret, mask, 0);
    String? out;
    try {
      out = SecretMask.unmask(
          m, "ffeeddccbbaa99887766554433221100ffeeddccbbaa9988", 0);
    } catch (_) {}
    expect(out, isNot(secret));
  });

  test("tool/mask_secrets.dart output feeds back into the app's unmask",
      () async {
    final r = await Process.run("dart", [
      "run",
      "tool/mask_secrets.dart"
    ], environment: {
      "LOCK_P1": "p1-secret-aaaa",
      "LOCK_P2": "p2-secret-bbbb",
      "LOCK_P3": "",
      "LOCK_P4": "p4",
      "GATE_KEY": "gate-key-1234"
    });
    expect(r.exitCode, 0, reason: "${r.stderr}");
    final env = {
      for (final l in (r.stdout as String).trim().split("\n"))
        l.split("=").first: l.substring(l.indexOf("=") + 1)
    };
    final m = env["LOCK_MASK"]!;
    expect(SecretMask.unmask(env["LOCK_P1_M"]!, m, 0), "p1-secret-aaaa");
    expect(SecretMask.unmask(env["LOCK_P2_M"]!, m, 1), "p2-secret-bbbb");
    expect(env["LOCK_P3_M"], isEmpty);
    expect(SecretMask.unmask(env["GATE_KEY_M"]!, m, 4), "gate-key-1234");
    expect(env["LOCK_P1_M"]!.contains("p1-secret"), isFalse);
  });
}
