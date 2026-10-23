/// Turns native integrity signals into the tag that is mixed into key derivation.
///
/// A clean run yields the empty tag, so keys are exactly what the server and other
/// clean installs derive. Anything else (re-signed APK, debugger, Frida, Xposed)
/// yields a different tag => a different key => files simply fail to open and gate
/// tokens are refused, with no error message that points at the cause.
class Tamper {
  Tamper._();

  /// Comma-separated lowercase SHA-256 hex digests of acceptable signing
  /// certificates (upload key, and Google's Play app-signing key for Play
  /// installs). Empty in dev builds => the certificate check is skipped.
  static const String _expectedCsv = String.fromEnvironment("EXPECTED_CERTS");

  static Set<String> get expectedCerts => parseCerts(_expectedCsv);

  static Set<String> parseCerts(String csv) => csv
      .split(",")
      .map((c) => c.replaceAll(":", "").trim().toLowerCase())
      .where((c) => c.length == 64)
      .toSet();

  /// [flags] bit 1 debugger, 2 frida, 4 xposed. Root hint (8) is reported by the
  /// native side but deliberately ignored here: too many honest users have it.
  static String environmentTag({
    required String? cert,
    required int flags,
    Set<String>? expected,
  }) {
    final exp = expected ?? expectedCerts;
    final problems = <String>[];
    if (exp.isNotEmpty && (cert == null || !exp.contains(cert.toLowerCase()))) {
      problems.add("sig");
    }
    final active = flags & 0x7;
    if (active != 0) problems.add("f$active");
    return problems.isEmpty ? "" : "tainted:${problems.join("+")}";
  }
}
