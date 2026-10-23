import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/locked_config_codec.dart";
import "package:oversea/features/add/importer.dart";

const _vless =
    "vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls&sni=example.com#A";

void main() {
  tearDown(() => LockedConfigCodec.environmentTag = "");

  test("plain Xray links import; other protocols are counted as skipped",
      () async {
    final out =
        await Importer.fromText("$_vless\nsocks5://u:p@h:1080\nhttp://h:8080");
    expect(out.isOk, isTrue);
    expect(out.configs.length, 1);
    expect(out.skipped, 2);
    expect(out.configs.single.locked, isFalse);
  });

  test("empty, oversized and non-config text are refused with a message key",
      () async {
    expect((await Importer.fromText("   ")).errorKey, "clipboard_empty");
    expect((await Importer.fromText("x" * (Importer.maxChars + 1))).errorKey,
        "import_too_big");
    expect((await Importer.fromText("hello world")).errorKey, "no_xray");
    expect((await Importer.fromText("socks5://u:p@h:1")).errorKey, "no_xray");
  });

  test(
      "a locked file imports as locked, with sanitised ad, verified creator and expiry",
      () async {
    final id = await CreatorIdentity.generate();
    final exp = DateTime.now().add(const Duration(days: 2));
    final blob = await LockedConfigCodec.encode(_vless,
        adText:
            "Join${String.fromCharCode(0x202E)} us${String.fromCharCode(0x200B)}!",
        telegramUrl: "https://t.me/chan",
        signer: id,
        gateCode: "0123456789abcdef0123456789abcdef",
        expiresAt: exp);
    final out = await Importer.fromText(blob);
    expect(out.isOk, isTrue, reason: "${out.errorKey}");
    final c = out.configs.single;
    expect(c.locked, isTrue);
    expect(c.adText, "Join us!");
    expect(c.telegramUrl, "https://t.me/chan");
    expect(c.creator, id.fingerprint);
    expect(c.gated, isTrue);
    expect(c.expiresAt, isNotNull);
  });

  test("a hostile Telegram link inside a file is dropped, not shown", () async {
    final blob = await LockedConfigCodec.encode(_vless,
        telegramUrl: "https://evil.example/t.me");
    expect((await Importer.fromText(blob)).configs.single.telegramUrl, isNull);
  });

  test("expired and tampered files are refused", () async {
    final expired = await LockedConfigCodec.encode(_vless,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
    expect((await Importer.fromText(expired)).errorKey, "file_expired");

    final good = await LockedConfigCodec.encode(_vless);
    final broken = good.substring(0, good.length - 6) +
        (good.endsWith("AAAAAA") ? "BBBBBB" : "AAAAAA");
    expect((await Importer.fromText(broken)).errorKey, "import_invalid");
  });

  test(
      "a locked file does not open in a tampered environment (and says nothing useful)",
      () async {
    final blob = await LockedConfigCodec.encode(_vless);
    LockedConfigCodec.environmentTag = "tainted:f2";
    expect((await Importer.fromText(blob)).errorKey, "import_invalid");
  });
}
