import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:cryptography/cryptography.dart";

import "creator_identity.dart";

/// Locked-config system (format v3).
///
/// What this protects against
/// --------------------------
/// The realistic threat is a "paste the file into a Telegram bot and get the
/// raw config back" decoder, and other channels re-branding your free configs.
/// v3 raises the bar on both compared to the naive scheme it replaces:
///
///   * Nothing useful is in cleartext. The old format wrote the rotation epoch
///     in the header and left the ad/telegram metadata outside the ciphertext.
///     Here only a 4-byte magic, a 1-byte version and a random per-file salt are
///     visible; config, ad text and telegram link are all inside AES-256-GCM.
///   * The key is not one string literal. [_assembleSecret] rebuilds the client
///     secret at runtime from scattered, XOR-masked parts, so a plain `strings`
///     dump of the binary does not reveal it.
///   * The per-file key is stretched with many HMAC rounds over (secret, salt),
///     so even a leaked secret cannot be turned into a fast offline oracle
///     without redoing the work per file.
///
/// Honest limitation
/// -----------------
/// Because the app itself can open the file offline, the material needed to
/// open it is, by definition, inside the app. A determined reverse engineer
/// with the right tooling can still recover it. The goal is not mathematical
/// impossibility — it is to make bulk, automated decoding expensive and brittle
/// (it breaks whenever [_parts] / the key generation is rotated in a new
/// app release), unlike the many apps whose single hardcoded key was pulled out
/// once and reused forever.
class LockedConfigCodec {
  // ── format constants ──────────────────────────────────────────────────
  static const List<int> _magic = [0x4F, 0x56, 0x53, 0x33]; // "OVS3"
  static const int _version = 3;

  /// Key generation. Bump this (and rotate [_parts]) in each app release
  /// so files made by a newer app stop opening in an older, cracked build and
  /// any extracted secret goes stale.
  static const int keyGeneration = 1;

  /// HMAC stretch rounds for the per-file key. Higher = slower per-file attack.
  static const int _stretchRounds = 4096;

  /// The client secret is split in four CI-injected parts
  /// (`--dart-define=LOCK_P1..LOCK_P4`, each a hex string from a repo secret).
  /// Nothing secret is committed: a plain source checkout has empty parts and
  /// [hasKey] is false. Four separate defines, XOR-masked and rejoined at
  /// runtime, mean the full key never sits contiguously in the binary.
  static const List<String> _parts = [
    String.fromEnvironment("LOCK_P1"),
    String.fromEnvironment("LOCK_P2"),
    String.fromEnvironment("LOCK_P3"),
    String.fromEnvironment("LOCK_P4"),
  ];

  /// Rotating mask mixed in when reassembling (not secret by itself).
  static const List<int> _mask = [
    0x5e,
    0x27,
    0x93,
    0xc1,
    0x6f,
    0x0a,
    0xd8,
    0x44
  ];

  static bool get hasKey => _parts.every((p) => p.isNotEmpty);

  static List<int> _assembleSecret() {
    if (!hasKey) {
      throw StateError("Lock key parts (LOCK_P1..P4) missing in this build.");
    }
    final out = <int>[];
    for (var p = 0; p < _parts.length; p++) {
      final bytes = utf8.encode(_parts[p]);
      for (var i = 0; i < bytes.length; i++) {
        out.add((bytes[i] ^ _mask[i % _mask.length] ^ (p * 31)) & 0xFF);
      }
    }
    return out;
  }

  /// Derive the AES-256 key for one file from the file's random salt. The salt
  /// makes every file's key unique, and the stretch makes deriving it costly to
  /// repeat at scale.
  static Future<SecretKey> _deriveKey(List<int> salt) async {
    final hmac = Hmac.sha256();
    final secret = SecretKey([
      ..._assembleSecret(),
      ...utf8.encode("ovsea|v3|gen$keyGeneration"),
    ]);
    // Initial block binds salt + domain, then iterate to stretch.
    var acc = (await hmac.calculateMac(
      [...salt, ...utf8.encode("ovsea-lock-v3")],
      secretKey: secret,
    ))
        .bytes;
    for (var i = 1; i < _stretchRounds; i++) {
      acc = (await hmac.calculateMac(acc, secretKey: secret)).bytes;
    }
    return SecretKey(acc); // 32 bytes → AES-256
  }

  /// Locks a raw Xray config (and optional owner ad / telegram link) into a
  /// base64url blob suitable for writing to a `.ovsea` file or sharing as text.
  ///
  /// When [signer] is given, the file carries the creator's public key and an
  /// Ed25519 signature over (config, ad, link, generation). Opening it reports who
  /// made it, and any later edit of the ad or link invalidates the signature.
  static Future<String> encode(
    String plaintextConfig, {
    String? adText,
    String? telegramUrl,
    CreatorIdentity? signer,
  }) async {
    final ad = (adText != null && adText.isNotEmpty) ? adText : null;
    final tg =
        (telegramUrl != null && telegramUrl.isNotEmpty) ? telegramUrl : null;
    final payload = jsonEncode({
      "c": plaintextConfig,
      if (ad != null) "a": ad,
      if (tg != null) "t": tg,
      "g": keyGeneration,
      if (signer != null) ...{
        "p": base64.encode(signer.publicKey),
        "s": base64.encode(await signer
            .sign(_signedBytes(plaintextConfig, ad, tg, keyGeneration))),
      },
    });

    final rnd = Random.secure();
    final salt =
        Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final key = await _deriveKey(salt);

    // Header (magic + version + generation + salt) is authenticated as AAD so
    // it cannot be swapped without failing decryption.
    final header = Uint8List.fromList([
      ..._magic,
      _version,
      keyGeneration & 0xFF,
      ...salt,
    ]);

    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      utf8.encode(payload),
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

  /// Opens a locked blob and returns the structured envelope.
  static Future<ConfigEnvelope> decodeConfig(String blobBase64) async {
    final bytes = base64Url.decode(_normalize(blobBase64.trim()));

    const headerLen = 4 + 1 + 1 + 16; // magic+ver+gen+salt
    if (bytes.length < headerLen + 12 + 16) {
      throw const FormatException("Locked blob too short / corrupt");
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException("Not a valid Oversea locked config");
      }
    }
    if (bytes[4] != _version) {
      throw FormatException("Unsupported lock version: ${bytes[4]}");
    }

    final salt = bytes.sublist(6, 6 + 16);
    final header = Uint8List.fromList(bytes.sublist(0, headerLen));
    final nonce = bytes.sublist(headerLen, headerLen + 12);
    final macBytes = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(headerLen + 12, bytes.length - 16);

    final key = await _deriveKey(salt);
    final aes = AesGcm.with256bits();
    final clear = await aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: key,
      aad: header,
    );
    final plain = utf8.decode(clear);

    final j = jsonDecode(plain) as Map<String, dynamic>;
    final c = j["c"] as String;
    final a = j["a"] as String?;
    final t = j["t"] as String?;
    final g = (j["g"] as num?)?.toInt() ?? 0;

    String? creator;
    final p = j["p"] as String?;
    final sg = j["s"] as String?;
    if (p != null && sg != null) {
      try {
        final pub = base64.decode(p);
        final sig = base64.decode(sg);
        if (await CreatorIdentity.verify(_signedBytes(c, a, t, g), sig, pub)) {
          creator = fingerprintOf(pub);
        }
      } catch (_) {
        // malformed signature material => treated as unsigned
      }
    }
    return ConfigEnvelope(c, adText: a, telegramUrl: t, creator: creator);
  }

  /// Canonical bytes the signature covers. A JSON array keeps field boundaries
  /// unambiguous (no "ab"+"c" vs "a"+"bc" confusion).
  static List<int> _signedBytes(String c, String? a, String? t, int g) =>
      utf8.encode("ovsea-sig-v1\n${jsonEncode([c, a ?? "", t ?? "", g])}");

  /// Cheap check whether a string looks like one of our v3 locked blobs.
  static bool looksLocked(String s) {
    try {
      final b = base64Url.decode(_normalize(s.trim()));
      return b.length >= 4 &&
          b[0] == _magic[0] &&
          b[1] == _magic[1] &&
          b[2] == _magic[2] &&
          b[3] == _magic[3];
    } catch (_) {
      return false;
    }
  }

  static String _normalize(String s) {
    final mod = s.length % 4;
    return mod == 0 ? s : s + ("=" * (4 - mod));
  }
}

/// Structured result from [LockedConfigCodec.decodeConfig].
class ConfigEnvelope {
  final String config;
  final String? adText;
  final String? telegramUrl;

  /// Fingerprint of the creator whose signature verified, or null when the file is
  /// unsigned or the signature does not match.
  final String? creator;
  const ConfigEnvelope(this.config,
      {this.adText, this.telegramUrl, this.creator});
}
