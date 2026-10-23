import "package:flutter_test/flutter_test.dart";
import "package:oversea/data/exit_ip.dart";

void main() {
  test("parses the ipwho.is shape", () {
    final i = ExitInfo.parse(
        '{"ip":"203.0.113.7","success":true,"country":"Germany","country_code":"DE"}')!;
    expect(i.ip, "203.0.113.7");
    expect(i.country, "Germany");
    expect(i.label, "\u{1F1E9}\u{1F1EA} Germany");
  });

  test("garbage, failures and missing ip are rejected", () {
    expect(ExitInfo.parse("nope"), isNull);
    expect(ExitInfo.parse("[]"), isNull);
    expect(ExitInfo.parse('{"success":false,"message":"limit"}'), isNull);
    expect(ExitInfo.parse('{"ip":"","success":true}'), isNull);
  });

  test("label degrades gracefully", () {
    expect(const ExitInfo("1.2.3.4").label, "");
    expect(const ExitInfo("1.2.3.4", country: "Peru").label, "Peru");
  });
}
