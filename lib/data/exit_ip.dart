import "dart:async";
import "dart:convert";
import "dart:io";

import "../domain/xray_config_builder.dart";

/// What the outside world sees when this phone's traffic leaves the tunnel.
class ExitInfo {
  final String ip;
  final String? country;
  final String? countryCode;
  const ExitInfo(this.ip, {this.country, this.countryCode});

  /// "🇩🇪 Germany" style label (flag only when the code is two letters).
  String get label {
    final cc = countryCode;
    final flag = cc != null && cc.length == 2
        ? String.fromCharCodes(
            cc.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41))
        : "";
    final name = country ?? "";
    return [flag, name].where((e) => e.isNotEmpty).join(" ");
  }

  static ExitInfo? parse(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      final ip = j["ip"];
      if (ip is! String || ip.isEmpty || j["success"] == false) return null;
      return ExitInfo(ip,
          country: j["country"] as String?,
          countryCode: j["country_code"] as String?);
    } on FormatException {
      return null;
    }
  }
}

/// Asks a public "what is my IP" service *through* the tunnel, using the loopback probe
/// proxy of the running core ([ProbeEndpoint]). The app itself is excluded from the VPN,
/// so a direct request would show the real IP instead of the exit IP.
Future<ExitInfo?> fetchExitInfo(
  ProbeEndpoint probe, {
  String url = "https://ipwho.is/",
  int attempts = 4,
  Duration retryDelay = const Duration(seconds: 2),
}) async {
  for (var i = 0; i < attempts; i++) {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy =
          ((_) => "PROXY ${probe.user}:${probe.pass}@127.0.0.1:${probe.port}");
    try {
      final req = await c.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final info = ExitInfo.parse(await utf8.decodeStream(res));
        if (info != null) return info;
      }
    } catch (_) {
      // the tunnel may still be warming up; retry below
    } finally {
      c.close(force: true);
    }
    if (i < attempts - 1) await Future<void>.delayed(retryDelay);
  }
  return null;
}
