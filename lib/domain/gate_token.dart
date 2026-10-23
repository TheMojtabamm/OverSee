import "dart:convert";

import "package:crypto/crypto.dart";

/// Client token for the Oversea gate (server/internal/gate). A gated server
/// refuses any connection without it, so a decoded vless:// link is useless in
/// other apps. Same construction as the Go side; the shared test vector keeps
/// them identical.
class GateToken {
  GateToken._();

  /// Injected at build time (`--dart-define=GATE_KEY=...`, a CI secret). Empty in a
  /// plain checkout, in which case gated configs cannot be connected or created.
  static const String _key = String.fromEnvironment("GATE_KEY");

  static bool get available => _key.isNotEmpty;

  /// Header name the gate reads.
  static const header = "X-Oversea-Auth";

  static String current({DateTime? now}) => forKey(_key, now ?? DateTime.now());

  static String forKey(String key, DateTime now) {
    final day = now.toUtc().millisecondsSinceEpoch ~/ 86400000;
    final mac = Hmac(sha256, utf8.encode(key))
        .convert(utf8.encode("ovsea-gate-v1|$day"));
    return "$day.${mac.toString()}";
  }
}
