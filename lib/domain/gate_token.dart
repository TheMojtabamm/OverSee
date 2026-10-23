import "dart:convert";
import "dart:math";

import "package:crypto/crypto.dart";

import "locked_config_codec.dart";
import "secret_mask.dart";

/// Client token for the Oversea gate (server/internal/gate).
///
///   token = <codeId>.<day>.hex(HMAC(appKey, "ovsea-gate-v2|"+code+"|"+creatorFp+"|"+day))
///
/// One MAC covers all three facts the server checks: this is the Oversea app
/// (appKey), the lock's secret code is on the server's allow-list, and the file
/// was signed by the creator that owns that code (creatorFp comes from the
/// *verified* signature of the file being used). Same construction as the Go side;
/// the shared test vector keeps them identical.
class GateToken {
  GateToken._();

  /// Injected at build time (`--dart-define=GATE_KEY=...`, a CI secret). Empty in a
  /// plain checkout, in which case gated configs cannot be created or connected.
  static const String _embeddedKey = String.fromEnvironment("GATE_KEY");
  static const String _maskHex = String.fromEnvironment("LOCK_MASK");

  /// The real app key (the embedded value is masked in CI builds; see SecretMask).
  static String get _appKey => SecretMask.unmask(_embeddedKey, _maskHex, 4);

  static bool get available => _embeddedKey.isNotEmpty;

  /// Header name the gate reads.
  static const header = "X-Oversea-Auth";

  /// A fresh random per-lock code: 128 bits, 32 hex chars.
  static String newCode() {
    final r = Random.secure();
    return List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
  }

  static String codeId(String code) => sha256
      .convert(utf8.encode("ovsea-code-id|$code"))
      .toString()
      .substring(0, 16);

  /// Token for a gated lock using this build's app key.
  static String current(String code, String creatorFp, {DateTime? now}) =>
      forKey(_appKey, code, creatorFp, now ?? DateTime.now(),
          envTag: LockedConfigCodec.environmentTag);

  /// [envTag] is "" in a clean environment (exactly what the server computes). A
  /// tampered environment mixes in a tag, so its token is silently wrong.
  static String forKey(
      String appKey, String code, String creatorFp, DateTime now,
      {String envTag = ""}) {
    final day = now.toUtc().millisecondsSinceEpoch ~/ 86400000;
    final key = envTag.isEmpty ? appKey : "$appKey|env:$envTag";
    final mac = Hmac(sha256, utf8.encode(key))
        .convert(utf8.encode("ovsea-gate-v2|$code|$creatorFp|$day"));
    return "${codeId(code)}.$day.$mac";
  }

  /// The line the creator adds to the server's allow-list.
  static String allowListLine(String code, String creatorFp,
          {String note = ""}) =>
      "$code $creatorFp${note.isEmpty ? "" : " $note"}";
}
