import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/domain/config_parser.dart";

void main() {
  test("parses vless, trojan, ss and vmess as Xray", () {
    final vmess = "vmess://${base64.encode(utf8.encode(jsonEncode({
          "ps": "V",
          "add": "h.com",
          "port": 443
        })))}";
    final text = [
      "vless://u@a.com:443?security=tls#A",
      "trojan://p@b.com:443#B",
      "ss://YWVzOnBhc3M=@c.com:8388#C",
      vmess,
    ].join("\n");
    final r = ConfigParser.parseMany(text);
    expect(r.length, 4);
    expect(r.every((c) => c.protocol.isXray), isTrue);
    expect(r.first.host, "a.com");
    expect(r.first.port, 443);
  });

  test("socks/http/unknown are not Xray", () {
    final r =
        ConfigParser.parseMany("socks5://u:p@h:1080\nhttp://h:8080\nfoo://bar");
    expect(r.where((c) => c.protocol.isXray), isEmpty);
  });

  test("comments and blank lines are skipped", () {
    expect(ConfigParser.parseMany("\n# c\n// c\n\n"), isEmpty);
  });
}
