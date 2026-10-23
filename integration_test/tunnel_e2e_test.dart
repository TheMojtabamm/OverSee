// Runs on an Android emulator (tool/vpn_e2e.sh): starts the REAL VpnService + Xray tun
// against a local Xray server and prints markers the host script waits for. The host then
// checks, from `adb shell` (a UID that goes through the VPN), that DNS and TCP work.
import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:oversea/data/exit_ip.dart";
import "package:oversea/data/tunnel_service.dart";
import "package:oversea/domain/tunnel_settings.dart";
import "package:oversea/domain/xray_config_builder.dart";

const _link = String.fromEnvironment("E2E_LINK");
// "plain" = phone DNS goes through the tunnel as ordinary traffic; "doh" = resolver inside the core.
const _dns = String.fromEnvironment("E2E_DNS", defaultValue: "plain");

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("tunnel comes up, the UI is told, traffic flows", (t) async {
    expect(_link, isNotEmpty, reason: "E2E_LINK not provided");
    final svc = TunnelService();

    expect(await svc.prepare(), isTrue,
        reason: "VPN consent must be pre-granted (appops ACTIVATE_VPN)");

    final r = Random.secure();
    final probe = ProbeEndpoint(20000 + r.nextInt(30000), "e2e", "e2e-pass-1");
    final json = XrayConfigBuilder.build(
        _link,
        TunnelOptions(
          probe: probe,
          logLevel: "info",
          dohServers: _dns == "plain"
              ? const []
              : const [
                  "https://1.1.1.1/dns-query",
                  "https://8.8.8.8/dns-query"
                ],
        ));

    final seen = <TunnelPhase>[];
    final connected = Completer<void>();
    final sub = svc.states.listen((s) {
      seen.add(s.phase);
      if (s.phase == TunnelPhase.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    await svc.start(
        configJson: json, label: "e2e", settings: const TunnelSettings());
    await connected.future.timeout(const Duration(seconds: 30),
        onTimeout: () => fail("UI never received 'connected'; saw $seen"));
    // ignore: avoid_print
    print("E2E_TUNNEL_UP dns=$_dns");

    // The app itself is excluded from the VPN, so check the client->server leg through the
    // probe proxy (it exits through the same outbound the tunnel uses).
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy =
          ((_) => "PROXY ${probe.user}:${probe.pass}@127.0.0.1:${probe.port}");
    String probeResult;
    try {
      final req = await c.getUrl(Uri.parse("http://example.com/"));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await utf8.decodeStream(res);
      probeResult = "HTTP ${res.statusCode}, ${body.length} bytes";
    } catch (e) {
      probeResult = "FAILED: $e";
    } finally {
      c.close(force: true);
    }
    // ignore: avoid_print
    print("E2E_PROBE: $probeResult");

    final info = await fetchExitInfo(probe,
        url: "http://example.com/",
        attempts: 1); // not JSON: expect null, no crash
    // ignore: avoid_print
    print("E2E_EXITINFO_NONJSON: ${info == null ? 'null (ok)' : 'unexpected'}");

    // Give the host script time to run its adb-shell checks through the tunnel.
    await Future<void>.delayed(const Duration(seconds: 80));
    // ignore: avoid_print
    print("E2E_STATES: $seen");
    await svc.stop();
    await sub.cancel();
    expect(probeResult, startsWith("HTTP 200"));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
