import "dart:convert";

import "xray_config_builder.dart";

enum SplitMode { all, allow, deny }

enum DnsPreset {
  /// No resolver inside the core: the phone's DNS queries (to 1.1.1.1 / 1.0.0.1) simply travel
  /// through the tunnel like any other traffic. Fewest moving parts; the default.
  tunnel([]),
  cloudflare(["https://1.1.1.1/dns-query", "https://1.0.0.1/dns-query"]),
  google(["https://8.8.8.8/dns-query", "https://8.8.4.4/dns-query"]),
  quad9(["https://9.9.9.9/dns-query", "https://149.112.112.112/dns-query"]);

  final List<String> urls;
  const DnsPreset(this.urls);
}

/// User-facing tunnel preferences (no secrets; stored in plain preferences).
class TunnelSettings {
  final DnsPreset dns;
  final bool fragment;
  final bool ipv6;
  final bool bypassLan;
  final bool killSwitch;
  final SplitMode splitMode;
  final List<String> apps;

  const TunnelSettings({
    this.dns = DnsPreset.tunnel,
    this.fragment = false,
    this.ipv6 = false,
    this.bypassLan = true,
    this.killSwitch = true,
    this.splitMode = SplitMode.all,
    this.apps = const [],
  });

  TunnelOptions toOptions() => TunnelOptions(
        dohServers: dns.urls,
        fragment: fragment,
        ipv6: ipv6,
        bypassLan: bypassLan,
      );

  TunnelSettings copyWith({
    DnsPreset? dns,
    bool? fragment,
    bool? ipv6,
    bool? bypassLan,
    bool? killSwitch,
    SplitMode? splitMode,
    List<String>? apps,
  }) =>
      TunnelSettings(
        dns: dns ?? this.dns,
        fragment: fragment ?? this.fragment,
        ipv6: ipv6 ?? this.ipv6,
        bypassLan: bypassLan ?? this.bypassLan,
        killSwitch: killSwitch ?? this.killSwitch,
        splitMode: splitMode ?? this.splitMode,
        apps: apps ?? this.apps,
      );

  String toJson() => jsonEncode({
        // "dns2": the earlier "dns" key held a DoH choice that was the default; ignoring it once
        // moves everyone to the plain-through-the-tunnel default (they can pick DoH again).
        "dns2": dns.name,
        "fragment": fragment,
        "ipv6": ipv6,
        "bypassLan": bypassLan,
        "killSwitch": killSwitch,
        "splitMode": splitMode.name,
        "apps": apps,
      });

  factory TunnelSettings.fromJson(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return TunnelSettings(
        dns: DnsPreset.values.firstWhere((e) => e.name == j["dns2"],
            orElse: () => DnsPreset.tunnel),
        fragment: j["fragment"] == true,
        ipv6: j["ipv6"] == true,
        bypassLan: j["bypassLan"] != false,
        killSwitch: j["killSwitch"] != false,
        splitMode: SplitMode.values.firstWhere((e) => e.name == j["splitMode"],
            orElse: () => SplitMode.all),
        apps: ((j["apps"] as List?) ?? const []).whereType<String>().toList(),
      );
    } catch (_) {
      return const TunnelSettings();
    }
  }
}
