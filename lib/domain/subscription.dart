import "dart:convert";

import "config_parser.dart";
import "vpn_config.dart";

/// A subscription: a URL that returns a list of share links (plain text, or base64 of it).
/// The URL often carries a secret token, so [SubscriptionStore] keeps it in the vault.
class Subscription {
  final String id;
  final String name;
  final String url;

  /// When the list was last fetched successfully; null = never.
  final DateTime? updatedAt;
  final int count;

  /// A short, safe reason the last refresh failed (no URL, no body); null when it worked.
  final String? error;

  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.updatedAt,
    this.count = 0,
    this.error,
  });

  Subscription copyWith({
    String? name,
    String? url,
    DateTime? updatedAt,
    int? count,
    String? error,
    bool clearError = false,
  }) =>
      Subscription(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        updatedAt: updatedAt ?? this.updatedAt,
        count: count ?? this.count,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "url": url,
        "updatedAt": updatedAt?.toUtc().millisecondsSinceEpoch,
        "count": count,
        "error": error,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j["id"] as String,
        name: (j["name"] as String?) ?? "Subscription",
        url: j["url"] as String,
        updatedAt: (j["updatedAt"] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j["updatedAt"] as num).toInt(),
                isUtc: true),
        count: (j["count"] as num?)?.toInt() ?? 0,
        error: j["error"] as String?,
      );

  /// A friendly default name: the host of [url].
  static String nameFromUrl(String url) {
    final h = Uri.tryParse(url.trim())?.host ?? "";
    return h.isEmpty ? "Subscription" : h;
  }

  /// Only http(s) URLs with a host.
  static bool isValidUrl(String url) {
    final u = Uri.tryParse(url.trim());
    return u != null &&
        u.hasAuthority &&
        u.host.isNotEmpty &&
        (u.scheme == "https" || u.scheme == "http");
  }

  /// Parses a subscription body. Accepts plain lines of links, base64 of such lines
  /// (standard or URL-safe), or a mix. Returns only the protocols the app can run.
  static List<VpnConfig> parseBody(String body,
      {required String subId, String subName = ""}) {
    var text = body.trim();
    if (text.isEmpty) return const [];
    if (!_looksLikeLinks(text)) {
      final decoded = _tryBase64(text);
      if (decoded != null) text = decoded;
    }
    return ConfigParser.parseMany(text,
            source: subName.isEmpty ? "subscription" : "Subscription: $subName",
            channelRef: subId)
        .where((c) => c.protocol.isXray)
        .toList();
  }

  static bool _looksLikeLinks(String t) =>
      RegExp(r"^[a-zA-Z][a-zA-Z0-9+.-]*://", multiLine: true).hasMatch(t);

  static String? _tryBase64(String t) {
    try {
      var s = t
          .replaceAll(RegExp(r"\s"), "")
          .replaceAll("-", "+")
          .replaceAll("_", "/");
      while (s.length % 4 != 0) {
        s += "=";
      }
      final out = utf8.decode(base64.decode(s));
      return _looksLikeLinks(out) ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Replaces the configs that came from subscription [subId] with [fetched]. Configs that are
  /// still in the list keep their id (so the selection and ping survive a refresh); ones that
  /// vanished are dropped; a link the user also added by hand is not duplicated.
  static List<VpnConfig> merge({
    required List<VpnConfig> current,
    required String subId,
    required List<VpnConfig> fetched,
  }) {
    final others = current.where((c) => c.channelRef != subId).toList();
    final mine = {
      for (final c in current.where((c) => c.channelRef == subId)) c.raw: c
    };
    final taken = others.map((c) => c.raw).toSet();
    final out = [...others];
    for (final f in fetched) {
      if (!taken.add(f.raw)) continue;
      final old = mine[f.raw];
      out.add(old == null ? f : f.copyWith(id: old.id));
    }
    return out;
  }
}
