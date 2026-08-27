import "dart:convert";
import "dart:typed_data";

import "package:cryptography/cryptography.dart";

/// Locked-config system: encrypts a config so it can only be opened by our app.
///
/// Design goals
/// ------------
/// A static, hardcoded key is the classic weakness: extract it once, reuse it
/// forever. Two things prevent that here:
///
/// 1. Time-rotating key. The AES key is derived per "epoch" (a period computed
///    from the current UTC date). A key pulled out for today stops working once
///    the epoch advances, so a scraper has to re-extract continuously.
///
///        periodKey = HMAC-SHA256(clientKeyMaterial, "v1|<epoch>|<serverComponent>")
///
/// 2. No usable secret lives in this repository. [_clientKeyMaterial] is injected
///    at build time via a compile-time define (see build workflow), NOT committed.
///    A fresh checkout of the source contains an empty value, so reading the
///    public repo reveals the algorithm but no key — and the algorithm alone
///    cannot open anything.
///
/// Hybrid mode (recommended)
/// -------------------------
/// When [decode] is given a [serverComponentFor] callback, part of the key comes
/// from your own server per epoch. Then even a fully reverse-engineered binary
/// cannot derive keys offline: it must reach your endpoint, which you rate-limit
/// and monitor for abusive patterns.
///
/// Honest limitation: no client-side lock on an open platform is unbreakable.
/// The goal is to make breaking it expensive enough that it is not worth it for
/// the overwhelming majority of cases.
class LockedConfigCodec {
  /// Injected at build time via `--dart-define=LOCK_CLIENT_KEY=...` from a CI
  /// secret. Intentionally empty in a plain source checkout so the repository
  /// itself carries no usable key. Must match the key held by the server-side
  /// config generator.
  static const String _clientKeyMaterial =
      String.fromEnvironment("LOCK_CLIENT_KEY", defaultValue: "");

  /// Days per key rotation. 1 = daily. Set to 7 for weekly, etc.
  static const int rotationDays = 1;

  static const List<int> _magic = [0x4C, 0x4B, 0x31, 0x00]; // marker
  static const int _version = 1;

  /// Current epoch number based on UTC date. The server generator must run the
  /// exact same computation.
  static int currentEpoch({DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    final daysSinceUnix = t.millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
    return daysSinceUnix ~/ rotationDays;
  }

  static bool get hasKey => _clientKeyMaterial.isNotEmpty;

  static Future<SecretKey> _deriveKey(int epoch, String serverComponent) async {
    final hmac = Hmac.sha256();
    final info = utf8.encode("v1|$epoch|$serverComponent");
    final mac = await hmac.calculateMac(
      info,
      secretKey: SecretKey(utf8.encode(_clientKeyMaterial)),
    );
    return SecretKey(mac.bytes); // 32 bytes -> AES-256 key
  }

  /// Locks a raw config into a base64url blob. This is the "generate" side and
  /// normally runs in the server-side tool; it is here so the same code path can
  /// also be exercised in tests and local builds that carry the key.
  static Future<String> encode(
    String plaintextConfig, {
    int? epoch,
    String serverComponent = "",
  }) async {
    if (!hasKey) {
      throw StateError("No key material (LOCK_CLIENT_KEY) available at build.");
    }
    final ep = epoch ?? currentEpoch();
    final key = await _deriveKey(ep, serverComponent);

    // Header (magic + version + epoch) is authenticated as AAD so it can't be
    // tampered with.
    final header = Uint8List.fromList([..._magic, _version, ..._uint32be(ep)]);

    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      utf8.encode(plaintextConfig),
      secretKey: key,
      aad: header,
    );

    final blob = <int>[
      ...header,
      ...box.nonce, // 12 bytes
      ...box.cipherText,
      ...box.mac.bytes, // 16 bytes
    ];
    return base64Url.encode(blob);
  }

  /// Opens a locked blob. In hybrid mode, provide [serverComponentFor] to fetch
  /// the server component matching the epoch embedded in the blob.
  static Future<String> decode(
    String blobBase64, {
    Future<String> Function(int epoch)? serverComponentFor,
  }) async {
    if (!hasKey) {
      throw StateError("No key material (LOCK_CLIENT_KEY) available at build.");
    }
    final bytes = base64Url.decode(_normalize(blobBase64));

    if (bytes.length < 4 + 1 + 4 + 12 + 16) {
      throw const FormatException("Locked blob too short / corrupt");
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException("Not a valid locked config");
      }
    }
    final version = bytes[4];
    if (version != _version) {
      throw FormatException("Unsupported lock version: $version");
    }
    final epoch = _readUint32be(bytes, 5);

    final serverComponent =
        serverComponentFor != null ? await serverComponentFor(epoch) : "";
    final key = await _deriveKey(epoch, serverComponent);

    final header = Uint8List.fromList(bytes.sublist(0, 9));
    final nonce = bytes.sublist(9, 21); // 12 bytes
    final macBytes = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(21, bytes.length - 16);

    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
      aad: header,
    );
    return utf8.decode(clear);
  }

  /// Cheap check whether a string looks like one of our locked blobs (no
  /// decryption attempted).
  static bool looksLocked(String s) {
    try {
      final b = base64Url.decode(_normalize(s.trim()));
      return b.length >= 9 &&
          b[0] == _magic[0] &&
          b[1] == _magic[1] &&
          b[2] == _magic[2] &&
          b[3] == _magic[3];
    } catch (_) {
      return false;
    }
  }

  // ---- helpers -------------------------------------------------------------

  static List<int> _uint32be(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static int _readUint32be(List<int> b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  static String _normalize(String s) {
    final clean = s.trim();
    final mod = clean.length % 4;
    return mod == 0 ? clean : clean + ("=" * (4 - mod));
  }
}
