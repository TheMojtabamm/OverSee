import "dart:convert";

import "package:http/http.dart" as http;

import "../models/vpn_config.dart";
import "config_parser.dart";
import "locked_config_codec.dart";

/// A channel that publishes free configs, shown in the in-app feed.
class FreeChannel {
  final String ref; // unique id (stats / attribution / revenue share)
  final String title;
  final String? telegramUrl;
  final int configCount;

  const FreeChannel({
    required this.ref,
    required this.title,
    this.telegramUrl,
    this.configCount = 0,
  });

  factory FreeChannel.fromJson(Map<String, dynamic> j) => FreeChannel(
        ref: j["ref"] as String,
        title: (j["title"] as String?) ?? j["ref"] as String,
        telegramUrl: j["telegramUrl"] as String?,
        configCount: (j["configCount"] as int?) ?? 0,
      );
}

/// The in-app free-config feed: a list of channels and their configs, shown
/// directly inside the app. Configs may be raw or locked; locked ones are opened
/// with [LockedConfigCodec]. The feed server is a separate service (behind a CDN)
/// — this class is only its client.
class FreeConfigsService {
  final String feedBaseUrl; // e.g. https://feed.example.com
  FreeConfigsService(this.feedBaseUrl);

  Future<List<FreeChannel>> channels() async {
    final res = await http
        .get(Uri.parse("$feedBaseUrl/v1/channels"),
            headers: {"User-Agent": "Oversea/1.0"})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception("Channel list fetch failed (${res.statusCode})");
    }
    final list = (jsonDecode(res.body) as Map)["channels"] as List;
    return list
        .map((e) => FreeChannel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<VpnConfig>> configsOf(FreeChannel channel) async {
    final res = await http
        .get(Uri.parse("$feedBaseUrl/v1/channels/${channel.ref}/configs"),
            headers: {"User-Agent": "Oversea/1.0"})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception("Channel configs fetch failed (${res.statusCode})");
    }

    final items = (jsonDecode(res.body) as Map)["configs"] as List;
    final out = <VpnConfig>[];
    for (final it in items) {
      final m = it as Map<String, dynamic>;
      final data = m["data"] as String; // raw or locked blob
      final unlocked = LockedConfigCodec.looksLocked(data)
          ? await LockedConfigCodec.decode(data)
          : data;
      final cfg = ConfigParser.parseLine(unlocked,
          source: "free", channelRef: channel.ref);
      if (cfg != null) out.add(cfg);
    }
    return out;
  }
}
