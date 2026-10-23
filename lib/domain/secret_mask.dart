import "dart:convert";

/// Build-time masking of embedded secrets.
///
/// A secret passed as `--dart-define=NAME=value` sits in the binary as that literal
/// string, so `strings libapp.so | grep value` finds it. CI therefore passes
/// `hex(secret XOR mask)` plus a fresh random `mask` for every build
/// (`tool/mask_secrets.dart`), and the app recovers the secret at runtime. The
/// literal never appears in the binary and the embedded bytes differ per build.
///
/// This defeats string search and cross-build diffing, nothing more: anyone who
/// runs the app (or reads the code that reverses the mask) still recovers it.
class SecretMask {
  SecretMask._();

  /// [index] separates secrets so equal values don't mask to equal bytes.
  static List<int> apply(List<int> data, List<int> mask, int index) => [
        for (var i = 0; i < data.length; i++)
          (data[i] ^ mask[i % mask.length] ^ ((index * 31 + i * 7) & 0xFF)) &
              0xFF
      ];

  static String hexOf(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();

  static List<int> bytesOfHex(String h) => [
        for (var i = 0; i + 1 < h.length; i += 2)
          int.parse(h.substring(i, i + 2), radix: 16)
      ];

  /// What CI embeds for [secret].
  static String mask(String secret, String maskHex, int index) =>
      hexOf(apply(utf8.encode(secret), bytesOfHex(maskHex), index));

  /// What the app does with the embedded value. With no mask (dev builds and tests)
  /// the value is the secret itself.
  static String unmask(String embedded, String maskHex, int index) {
    if (maskHex.isEmpty || embedded.isEmpty) return embedded;
    return utf8.decode(apply(bytesOfHex(embedded), bytesOfHex(maskHex), index));
  }
}
