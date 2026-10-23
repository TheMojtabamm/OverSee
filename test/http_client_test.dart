import "dart:typed_data";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/core/http_client.dart";

void main() {
  // Pin computed independently with:
  //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
  const expected = "l3y4AZu7wk/u1/z8p1thDCXSnmCMdq3BUZZS+kesB/k=";

  test("SPKI pin of a real certificate matches openssl", () {
    final der = File("test/fixtures/test_cert.der").readAsBytesSync();
    expect(spkiPin(der), expected);
  });

  test("malformed DER does not yield a pin", () {
    expect(() => spkiPin(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });

  test("prod client without pins is refused, with pins is allowed", () {
    expect(
        () => buildHttpClient(
            baseUrl: "https://example.com", pins: const [], prod: true),
        throwsStateError);
    expect(
        () => buildHttpClient(
            baseUrl: "https://example.com", pins: const [expected], prod: true),
        returnsNormally);
  });

  test("dev client without pins is allowed", () {
    expect(
        () => buildHttpClient(
            baseUrl: "https://example.com", pins: const [], prod: false),
        returnsNormally);
  });
}
