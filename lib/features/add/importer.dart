import "../../domain/ad_content.dart";
import "../../domain/config_parser.dart";
import "../../domain/locked_config_codec.dart";
import "../../domain/vpn_config.dart";

/// Result of importing text (pasted, picked from a file, or opened from another app).
class ImportOutcome {
  final List<VpnConfig> configs;

  /// A strings.dart key describing the failure; null on success.
  final String? errorKey;

  /// Plain configs skipped because they aren't Xray protocols.
  final int skipped;
  const ImportOutcome.ok(this.configs, {this.skipped = 0}) : errorKey = null;
  const ImportOutcome.error(this.errorKey)
      : configs = const [],
        skipped = 0;

  bool get isOk => errorKey == null;
}

/// Turns text into configs ready to store. Pure (no storage, no UI) so it can be
/// tested and reused by the Add screen and by "open with Oversea".
///
/// Input limits: anything over [maxChars] is refused before parsing, so a shared
/// file can't make the app churn.
class Importer {
  Importer._();

  static const maxChars = 200000;

  static Future<ImportOutcome> fromText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      return const ImportOutcome.error("clipboard_empty");
    }
    if (text.length > maxChars) {
      return const ImportOutcome.error("import_too_big");
    }

    if (LockedConfigCodec.looksLocked(text)) {
      return _locked(text);
    }

    final all = ConfigParser.parseMany(text);
    final xray = all.where((c) => c.protocol.isXray).toList();
    if (xray.isEmpty) return const ImportOutcome.error("no_xray");
    return ImportOutcome.ok(xray, skipped: all.length - xray.length);
  }

  static Future<ImportOutcome> _locked(String blob) async {
    if (!LockedConfigCodec.hasKey) return const ImportOutcome.error("no_key");
    final ConfigEnvelope env;
    try {
      env = await LockedConfigCodec.decodeConfig(blob);
    } catch (_) {
      // Deliberately uninformative: don't tell an attacker which check failed.
      return const ImportOutcome.error("import_invalid");
    }
    if (env.isExpired()) return const ImportOutcome.error("file_expired");

    final parsed = ConfigParser.parseMany(env.config)
        .where((c) => c.protocol.isXray)
        .toList();
    if (parsed.isEmpty) return const ImportOutcome.error("no_xray");

    // Locked configs keep their server hidden and cannot be copied or re-shared.
    return ImportOutcome.ok([
      for (final c in parsed)
        VpnConfig(
          id: c.id,
          name: c.name,
          protocol: c.protocol,
          raw: c.raw,
          source: "locked",
          adText: AdContent.text(env.adText),
          telegramUrl: AdContent.channelUrl(env.telegramUrl),
          locked: true,
          creator: env.creator,
          gateCode: env.gateCode,
          expiresAt: env.expiresAt,
        ),
    ]);
  }
}
