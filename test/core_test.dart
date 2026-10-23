import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/core/log.dart";
import "package:oversea/core/strings.dart";

void main() {
  test(
      "the app is English-only: one language, no empty strings, no Persian script",
      () {
    expect(S.table.keys.toList(), ["en"]);
    expect(S.supportedLocales.map((l) => l.languageCode), ["en"]);
    final persian = RegExp(r"[\u0600-\u06FF]");
    S.table["en"]!.forEach((k, v) {
      expect(v.trim(), isNotEmpty, reason: k);
      expect(persian.hasMatch(v), isFalse, reason: "$k contains Persian text");
    });
  });

  test("every string key used in lib/ exists in the table", () {
    final used = <String>{};
    final re = RegExp(r"""\.t\(\s*["']([a-z0-9_]+)["']\s*\)""");
    for (final f
        in Directory("lib").listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith(".dart")) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
      }
    }
    final missing = used.difference(S.table["en"]!.keys.toSet());
    expect(missing, isEmpty, reason: "keys used but not defined: $missing");
    expect(
        used.length, greaterThan(40)); // the scan really found the call sites
  });

  test("Log.redact scrubs config URIs", () {
    final r = Log.redact("failed vless://uuid@host:443?x=1#name and ss://abc");
    expect(r.contains("uuid"), isFalse);
    expect(r.contains("host"), isFalse);
    expect(r, contains("vless://<redacted>"));
    expect(r, contains("ss://<redacted>"));
  });
}
