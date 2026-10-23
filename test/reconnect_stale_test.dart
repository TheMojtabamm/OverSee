import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:oversea/core/strings.dart";
import "package:oversea/data/tunnel_service.dart";
import "package:oversea/domain/tunnel_settings.dart";
import "package:oversea/domain/vpn_config.dart";
import "package:oversea/features/configs/connect_flow.dart";
import "package:oversea/providers.dart";
import "package:shared_preferences/shared_preferences.dart";

class _Fake extends TunnelService {
  final log = <String>[];
  final _c = StreamController<TunnelState>.broadcast();
  @override
  Stream<TunnelState> get states => _c.stream;
  @override
  Future<bool> prepare() async => true;
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<void> start(
      {required String configJson,
      required String label,
      required TunnelSettings settings}) async {
    log.add("start");
    lastConfig = configJson;
    Future.delayed(const Duration(milliseconds: 20),
        () => _c.add(const TunnelState(TunnelPhase.connected)));
  }

  @override
  Future<void> stop() async {
    log.add("stop");
    Future.delayed(
        const Duration(milliseconds: 20), () => _c.add(TunnelState.idle));
  }

  String? lastConfig;
}

class _Configs extends ConfigsNotifier {
  final List<VpnConfig> items;
  _Configs(this.items);
  @override
  Future<List<VpnConfig>> build() async => items;
}

VpnConfig _cfg({String? gateCode}) => VpnConfig(
      id: "c1",
      name: "x",
      protocol: VpnProtocol.vless,
      host: "h.example.com",
      port: 443,
      raw:
          "vless://11111111-2222-3333-4444-555555555555@h.example.com:443?security=tls&sni=h.example.com&type=ws&path=%2Fws#x",
      source: "locked",
      locked: true,
      creator: "3FA9-0C21-B7D4-9E10",
      gateCode: gateCode,
    );

Future<(bool, _Fake)> _run(
  WidgetTester t, {
  required VpnConfig cfg,
  required TunnelPhase phase,
  required int? tokenDay,
}) async {
  SharedPreferences.setMockInitialValues({"vpn_disclosure_accepted_v1": true});
  final fake = _Fake();
  bool? result;
  await t.pumpWidget(ProviderScope(
    overrides: [
      tunnelServiceProvider.overrideWithValue(fake),
      configsProvider.overrideWith(() => _Configs([cfg])),
      tunnelStateProvider
          .overrideWith((ref) => Stream.value(TunnelState(phase))),
    ],
    child: MaterialApp(
      localizationsDelegates: const [S.delegate],
      supportedLocales: S.supportedLocales,
      home: Consumer(builder: (context, ref, _) {
        // In the app these are always alive because screens watch them.
        ref.watch(tunnelStateProvider);
        ref.watch(configsProvider);
        return TextButton(
          onPressed: () async {
            ref.read(activeConfigIdProvider.notifier).state = cfg.id;
            ref.read(tunnelTokenDayProvider.notifier).state = tokenDay;
            result = await reconnectIfStale(context, ref);
          },
          child: const Text("go"),
        );
      }),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
  await t.tap(find.text("go"));
  // stop -> (fake teardown 20ms) -> start -> (fake connect 20ms): give it fake time to finish
  var iters = 0;
  for (; iters < 200 && result == null; iters++) {
    await t.pump(const Duration(milliseconds: 50));
    // plugin mocks (shared_preferences) complete on the real event loop
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  return (result ?? false, fake);
}

const _haveGateKey = String.fromEnvironment("GATE_KEY") != "";

void main() {
  final today = currentTokenDay();

  testWidgets("a gated tunnel with yesterday's token is re-keyed quietly",
      (t) async {
    final (did, fake) = await _run(t,
        cfg: _cfg(gateCode: "0123456789abcdef0123456789abcdef"),
        phase: TunnelPhase.connected,
        tokenDay: today - 1);
    expect(did, isTrue);
    expect(fake.log, ["stop", "start"],
        reason: "stop, then start with a fresh token");
    expect(fake.lastConfig, contains("X-Oversea-Auth"));
    expect(fake.lastConfig, contains(".$today."),
        reason: "the new token carries today's day");
  }, skip: !_haveGateKey);

  testWidgets("same day: nothing happens", (t) async {
    final (did, fake) = await _run(t,
        cfg: _cfg(gateCode: "0123456789abcdef0123456789abcdef"),
        phase: TunnelPhase.connected,
        tokenDay: today);
    expect(did, isFalse);
    expect(fake.log, isEmpty);
  });

  testWidgets("not gated: nothing happens even if the day differs", (t) async {
    final (did, fake) = await _run(t,
        cfg: _cfg(), phase: TunnelPhase.connected, tokenDay: today - 3);
    expect(did, isFalse);
    expect(fake.log, isEmpty);
  });

  testWidgets("not connected: nothing happens", (t) async {
    final (did, fake) = await _run(t,
        cfg: _cfg(gateCode: "0123456789abcdef0123456789abcdef"),
        phase: TunnelPhase.disconnected,
        tokenDay: today - 1);
    expect(did, isFalse);
    expect(fake.log, isEmpty);
  });

  test("currentTokenDay matches the GateToken arithmetic", () {
    expect(currentTokenDay(DateTime.utc(2026, 5, 5, 23, 59)),
        DateTime.utc(2026, 5, 5).millisecondsSinceEpoch ~/ 86400000);
    expect(currentTokenDay(DateTime.utc(2026, 5, 6)),
        currentTokenDay(DateTime.utc(2026, 5, 5)) + 1);
  });
}
