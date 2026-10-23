import "package:flutter/foundation.dart";

/// App logger. Silent in release builds, and it scrubs anything that looks like
/// a proxy config URI so a config can never leak through logcat, even in debug.
class Log {
  Log._();

  static final RegExp _uri = RegExp(
    r"(vless|vmess|trojan|ss|socks5?|hysteria2?|tuic|wireguard)://\S+",
    caseSensitive: false,
  );

  static String redact(String s) =>
      s.replaceAllMapped(_uri, (m) => "${m.group(1)}://<redacted>");

  static void d(String message) {
    if (kReleaseMode) return;
    debugPrint(redact(message));
  }
}
