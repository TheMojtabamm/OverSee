import "package:flutter_test/flutter_test.dart";
import "package:oversea/data/ad_service.dart";
import "package:oversea/domain/ad_content.dart";
import "package:oversea/domain/tunnel_settings.dart";

void main() {
  group("AdContent.channelUrl allows only https Telegram links", () {
    test("accepts", () {
      expect(AdContent.channelUrl("https://t.me/mychannel"),
          "https://t.me/mychannel");
      expect(AdContent.channelUrl("@mychannel"), "https://t.me/mychannel");
      expect(AdContent.channelUrl(" https://telegram.me/x "),
          "https://telegram.me/x");
    });
    test("rejects", () {
      for (final bad in [
        null,
        "",
        "http://t.me/x",
        "https://evil.com/t.me/x",
        "https://t.me.evil.com/x",
        "https://user@t.me/x",
        "https://t.me:8443/x",
        "javascript:alert(1)",
        "tg://resolve?domain=x",
        "intent://x#Intent;end",
        "file:///etc/passwd",
      ]) {
        expect(AdContent.channelUrl(bad), isNull, reason: "$bad");
      }
    });
  });

  group("AdContent.text", () {
    test("strips control, zero-width and bidi characters and collapses space",
        () {
      final dirty = "Join${String.fromCharCode(0x202E)} us"
          "${String.fromCharCode(0x200B)}\n\n now${String.fromCharCode(0)}!";
      expect(AdContent.text(dirty), "Join us now!");
    });
    test("limits length and treats blank as null", () {
      expect(AdContent.text("x" * 500)!.length, AdContent.maxText);
      expect(AdContent.text("  \n\t "), isNull);
      expect(AdContent.text(null), isNull);
    });
  });

  group("AdService.mayShow (Play-safe pacing)", () {
    final now = DateTime(2026, 1, 1, 12);
    test("never on the very first connect", () {
      expect(
          AdService.mayShow(firstEverConnect: true, lastShown: null, now: now),
          isFalse);
    });
    test("allowed when nothing was shown recently", () {
      expect(
          AdService.mayShow(firstEverConnect: false, lastShown: null, now: now),
          isTrue);
    });
    test("capped by the minimum gap", () {
      expect(
          AdService.mayShow(
              firstEverConnect: false,
              lastShown: now.subtract(const Duration(minutes: 2)),
              now: now),
          isFalse);
      expect(
          AdService.mayShow(
              firstEverConnect: false,
              lastShown: now.subtract(const Duration(minutes: 6)),
              now: now),
          isTrue);
    });
  });

  group("TunnelSettings", () {
    test("defaults are the safe ones", () {
      const s = TunnelSettings();
      expect(s.killSwitch, isTrue);
      expect(s.ipv6, isFalse);
      expect(s.splitMode, SplitMode.all);
    });
    test("json round trip", () {
      final s = const TunnelSettings().copyWith(
        dns: DnsPreset.quad9,
        fragment: true,
        splitMode: SplitMode.deny,
        apps: ["a.b", "c.d"],
        killSwitch: false,
      );
      final r = TunnelSettings.fromJson(s.toJson());
      expect(r.dns, DnsPreset.quad9);
      expect(r.fragment, isTrue);
      expect(r.splitMode, SplitMode.deny);
      expect(r.apps, ["a.b", "c.d"]);
      expect(r.killSwitch, isFalse);
    });
    test("corrupt json falls back to defaults", () {
      expect(TunnelSettings.fromJson("{not json").killSwitch, isTrue);
    });
    test("DoH presets are IP-literal https URLs", () {
      for (final d in DnsPreset.values) {
        for (final u in d.urls) {
          expect(Uri.parse(u).scheme, "https");
          expect(RegExp(r"^\d+\.\d+\.\d+\.\d+$").hasMatch(Uri.parse(u).host),
              isTrue);
        }
      }
    });
  });
}
