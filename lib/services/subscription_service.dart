import "dart:convert";

import "package:http/http.dart" as http;

import "../models/vpn_config.dart";
import "config_parser.dart";

/// Subscription import: the user provides a subscription URL and we pull all of
/// its configs. The common format is a base64 body whose decoded text has one
/// URL-style config per line; some servers return raw text instead. Both handled.
class SubscriptionService {
  static Future<List<VpnConfig>> fetch(String url, {String? channelRef}) async {
    final res = await http
        .get(Uri.parse(url), headers: {"User-Agent": "Oversea/1.0"})
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception("Subscription fetch failed (status ${res.statusCode})");
    }

    final body = res.body.trim();
    final decoded = _maybeBase64(body);
    return ConfigParser.parseMany(decoded,
        source: "subscription", channelRef: channelRef);
  }

  /// If the whole body is base64, decode it; otherwise return the raw text.
  static String _maybeBase64(String body) {
    final compact = body.replaceAll(RegExp(r"\s"), "");
    if (body.contains("://")) return body; // already raw
    try {
      final padded = compact.length % 4 == 0
          ? compact
          : compact + ("=" * (4 - compact.length % 4));
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      return body;
    }
  }
}
