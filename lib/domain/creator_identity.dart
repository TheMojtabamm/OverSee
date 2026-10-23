import "dart:convert";
import "dart:math";

import "package:crypto/crypto.dart" show sha256;
import "package:cryptography/cryptography.dart";

/// Short, human-comparable fingerprint of an Ed25519 public key, e.g.
/// `3FA9-0C21-B7D4-9E10`. 64 bits is for recognising a creator, not for security
/// against a determined collision search; the full key is what is verified.
String fingerprintOf(List<int> publicKey) {
  final h = sha256.convert(publicKey).bytes.take(8);
  final hex =
      h.map((b) => b.toRadixString(16).padLeft(2, "0")).join().toUpperCase();
  return [for (var i = 0; i < 16; i += 4) hex.substring(i, i + 4)].join("-");
}

/// The signing identity of whoever creates locked files on this device.
///
/// It proves *who made a file*, so a channel owner can publish their fingerprint
/// and followers can tell an official file from a copy that someone decoded and
/// re-locked under their own name (that copy carries the copier's fingerprint).
/// It does not stop a determined attacker from re-locking; it makes that visible.
class CreatorIdentity {
  static final _algo = Ed25519();

  final List<int> seed; // 32 bytes — the only secret; store in secure storage
  final List<int> publicKey;
  const CreatorIdentity._(this.seed, this.publicKey);

  String get fingerprint => fingerprintOf(publicKey);
  String get seedBase64 => base64.encode(seed);

  static Future<CreatorIdentity> fromSeed(List<int> seed) async {
    final kp = await _algo.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return CreatorIdentity._(
        List.unmodifiable(seed), List.unmodifiable(pub.bytes));
  }

  static Future<CreatorIdentity> generate() {
    final r = Random.secure();
    return fromSeed(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  Future<List<int>> sign(List<int> message) async {
    final kp = await _algo.newKeyPairFromSeed(seed);
    return (await _algo.sign(message, keyPair: kp)).bytes;
  }

  static Future<bool> verify(
      List<int> message, List<int> signature, List<int> publicKey) async {
    if (publicKey.length != 32 || signature.length != 64) return false;
    try {
      return await _algo.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
