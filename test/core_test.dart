import "package:flutter_test/flutter_test.dart";
import "package:oversea/core/log.dart";
import "package:oversea/core/strings.dart";

void main() {
  test("every string key exists in both fa and en", () {
    final en = S.table["en"]!.keys.toSet();
    final fa = S.table["fa"]!.keys.toSet();
    expect(fa.difference(en), isEmpty, reason: "keys only in fa");
    expect(en.difference(fa), isEmpty, reason: "keys only in en");
    for (final lang in S.table.values) {
      expect(lang.values.every((v) => v.trim().isNotEmpty), isTrue);
    }
  });

  test("Log.redact scrubs config URIs", () {
    final r = Log.redact("failed vless://uuid@host:443?x=1#name and ss://abc");
    expect(r.contains("uuid"), isFalse);
    expect(r.contains("host"), isFalse);
    expect(r, contains("vless://<redacted>"));
    expect(r, contains("ss://<redacted>"));
  });
}
