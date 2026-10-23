// Renders the real screens with fake data, asserts they build without errors, and
// writes PNGs to build/shots/ so the UI can be looked at without a device.
//
//   flutter test test/ui_smoke_test.dart   ->  build/shots/*.png
import "dart:io";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:oversea/app.dart";
import "package:oversea/data/config_store.dart";
import "package:oversea/data/identity_store.dart";
import "package:oversea/data/tunnel_service.dart";
import "package:oversea/domain/vpn_config.dart";
import "package:oversea/features/configs/share_sheet.dart";
import "package:oversea/providers.dart";
import "package:shared_preferences/shared_preferences.dart";

class _MemVault implements Vault {
  final m = <String, String>{};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

class _FakeConfigs extends ConfigsNotifier {
  final List<VpnConfig> items;
  _FakeConfigs(this.items);
  @override
  Future<List<VpnConfig>> build() async => items;
}

class _FakeSince extends ConnectedSinceNotifier {
  @override
  DateTime? build() =>
      DateTime.now().subtract(const Duration(minutes: 12, seconds: 34));
}

VpnConfig cfg(String id, String name, VpnProtocol p,
        {String? host,
        bool locked = false,
        bool gated = false,
        DateTime? exp}) =>
    VpnConfig(
      id: id,
      name: name,
      protocol: p,
      host: host,
      port: 443,
      raw: "vless://x@$host:443#$name",
      source: locked ? "locked" : "manual",
      locked: locked,
      gateCode: gated ? "0123456789abcdef0123456789abcdef" : null,
      expiresAt: exp,
    );

final _samples = [
  cfg("1", "Frankfurt · Reality", VpnProtocol.vless, host: "fra.example.com"),
  cfg("2", "Channel gift", VpnProtocol.vless, locked: true, gated: true),
  cfg("3", "Amsterdam WS", VpnProtocol.vmess, host: "ams.example.com"),
  cfg("4", "Old promo", VpnProtocol.trojan,
      locked: true, exp: DateTime.now().subtract(const Duration(days: 2))),
];

Future<void> _loadFonts() async {
  const dir = "/tmp/flutter-sdk/bin/cache/artifacts/material_fonts";
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File("$dir/$f").readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }

  if (!Directory(dir).existsSync()) {
    return; // other machines: fall back to the test font
  }
  await load("Roboto", [
    "Roboto-Regular.ttf",
    "Roboto-Medium.ttf",
    "Roboto-Bold.ttf",
    "Roboto-Black.ttf"
  ]);
  await load("MaterialIcons", ["MaterialIcons-Regular.otf"]);
}

final _key = GlobalKey();

Future<void> _shot(WidgetTester t, String name) async {
  await t.runAsync(() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File("build/shots/$name.png")..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _show(
  WidgetTester t, {
  required String shot,
  List<VpnConfig> configs = const [],
  TunnelState tunnel = TunnelState.idle,
  ThemeMode mode = ThemeMode.dark,
  int tab = 0,
  bool onboarded = true,
  Map<String, int> ping = const {},
  bool connectedTimer = false,
  String? selected,
  Future<void> Function(WidgetTester)? then,
}) async {
  t.view.physicalSize = const Size(900, 1950);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(
      {"theme_v1": mode == ThemeMode.light ? "light" : "dark"});

  final container = ProviderContainer(overrides: [
    configsProvider.overrideWith(() => _FakeConfigs(configs)),
    tunnelStateProvider.overrideWith((ref) => Stream.value(tunnel)),
    identityStoreProvider.overrideWithValue(IdentityStore(vault: _MemVault())),
    onboardedProvider.overrideWith((ref) async => onboarded),
    if (connectedTimer) connectedSinceProvider.overrideWith(_FakeSince.new),
  ]);
  addTearDown(container.dispose);
  container.read(
      themeModeProvider); // starts loading the saved mode from preferences
  container.read(tabProvider.notifier).state = tab;
  if (selected != null) {
    container.read(selectedConfigIdProvider.notifier).state = selected;
  }
  if (tunnel.phase == TunnelPhase.connected) {
    container.read(activeConfigIdProvider.notifier).state =
        selected ?? configs.first.id;
  }
  ping.forEach((k, v) => container.read(pingProvider.notifier).set(k, v));

  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: RepaintBoundary(key: _key, child: const OverseaApp()),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  if (then != null) await then(t);
  await _shot(t, shot);
  expect(t.takeException(), isNull, reason: "$shot built with an exception");
}

void main() {
  setUpAll(_loadFonts);

  testWidgets("home — empty", (t) async {
    await _show(t, shot: "home_empty_dark");
    expect(find.text("Add a config"), findsOneWidget);
  });

  testWidgets("home — disconnected, list with ping", (t) async {
    await _show(t,
        shot: "home_idle_dark",
        configs: _samples,
        ping: {"1": 92, "2": 310, "3": 840, "4": -1},
        selected: "1");
    expect(find.text("Tap to connect"), findsOneWidget);
    expect(find.text("92 ms"), findsOneWidget);
  });

  testWidgets("home — connected with speed and timer", (t) async {
    await _show(
      t,
      shot: "home_connected_dark",
      configs: _samples,
      tunnel: const TunnelState(TunnelPhase.connected,
          up: 3 << 20, down: 118 << 20, upRate: 180 << 10, downRate: 4 << 20),
      selected: "1",
      connectedTimer: true,
      ping: {"1": 92},
    );
    expect(find.text("Connected"), findsWidgets);
    expect(find.textContaining("00:12:3"), findsOneWidget);
  });

  testWidgets("home — connecting (light)", (t) async {
    await _show(t,
        shot: "home_connecting_light",
        configs: _samples,
        tunnel: const TunnelState(TunnelPhase.connecting),
        mode: ThemeMode.light,
        selected: "3");
    expect(find.text("Connecting…"), findsOneWidget);
  });

  testWidgets("home — kill switch blocking", (t) async {
    await _show(t,
        shot: "home_blocked_dark",
        configs: _samples,
        tunnel: const TunnelState(TunnelPhase.blocked),
        selected: "1");
    expect(find.text("Blocked — connection lost"), findsOneWidget);
  });

  testWidgets("home — idle (light)", (t) async {
    await _show(t,
        shot: "home_idle_light",
        configs: _samples,
        mode: ThemeMode.light,
        ping: {"1": 92, "2": 310},
        selected: "2");
  });

  testWidgets("add", (t) async {
    await _show(t, shot: "add_dark", tab: 1);
    expect(find.text("Paste from clipboard"), findsOneWidget);
  });

  testWidgets("settings", (t) async {
    await _show(t, shot: "settings_dark", tab: 2);
    expect(find.text("Kill switch"), findsOneWidget);
  });

  testWidgets("settings (light)", (t) async {
    await _show(t, shot: "settings_light", tab: 2, mode: ThemeMode.light);
  });

  testWidgets("onboarding", (t) async {
    await _show(t, shot: "onboarding_dark", onboarded: false);
    expect(find.text("Skip"), findsOneWidget);
  });

  testWidgets("share sheet", (t) async {
    await _show(t, shot: "share_sheet_dark", configs: _samples, selected: "1",
        then: (t) async {
      final ctx = t.element(find.byType(Scaffold).first);
      showShareSheet(ctx, _samples.first);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
  });
}
