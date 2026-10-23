/// Owner-supplied ad text / channel link arrives inside a locked file, i.e. it is
/// third-party content shown in our app. It is size-limited, stripped of control
/// characters, and the link is restricted to Telegram over https, so a file cannot
/// smuggle in arbitrary phishing links or unbounded text.
class AdContent {
  AdContent._();

  static const maxText = 200;
  static const _hosts = {"t.me", "telegram.me", "telegram.dog"};

  static String? text(String? s) {
    if (s == null) return null;
    final out = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x09 || r == 0x0A || r == 0x0D) {
        out.write(" "); // whitespace controls become a space
      } else if (!_invisible(r)) {
        out.writeCharCode(r);
      }
    }
    final clean = out.toString().replaceAll(RegExp(r"\s+"), " ").trim();
    if (clean.isEmpty) return null;
    return clean.length > maxText ? clean.substring(0, maxText) : clean;
  }

  /// Control characters, zero-width characters and bidi overrides/isolates (the
  /// latter can make a link or message read differently from what it is).
  static bool _invisible(int r) =>
      r < 0x20 ||
      r == 0x7F ||
      (r >= 0x200B && r <= 0x200F) ||
      (r >= 0x2028 && r <= 0x202E) ||
      (r >= 0x2066 && r <= 0x2069) ||
      r == 0xFEFF;

  /// Returns a normalised https Telegram URL, or null if it isn't one.
  static String? channelUrl(String? s) {
    if (s == null) return null;
    final raw = s.trim();
    if (raw.isEmpty) return null;
    final u = Uri.tryParse(
        raw.startsWith("@") ? "https://t.me/${raw.substring(1)}" : raw);
    if (u == null ||
        u.scheme != "https" ||
        !_hosts.contains(u.host.toLowerCase())) {
      return null;
    }
    if (u.userInfo.isNotEmpty || (u.hasPort && u.port != 443)) return null;
    return u.toString();
  }
}
