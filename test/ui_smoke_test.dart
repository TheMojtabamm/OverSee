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
import "package:oversea/data/exit_ip.dart";
import "package:oversea/data/identity_store.dart";
import "package:oversea/data/tunnel_service.dart";
import "package:oversea/domain/subscription.dart";
import "package:oversea/domain/vpn_config.dart";
import "package:oversea/features/configs/gate_line_card.dart";
import "package:oversea/features/editor/config_editor_screen.dart";
import "package:oversea/features/subscriptions/subscriptions_screen.dart";
import "package:oversea/features/configs/share_sheet.dart";
import "package:oversea/features/settings/gate_allowlist_screen.dart";
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

class _FakeSubs extends SubscriptionsNotifier {
  final List<Subscription> items;
  _FakeSubs(this.items);
  @override
  Future<List<Subscription>> build() async => items;
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
  final root = Platform.environment["FLUTTER_ROOT"] ?? "/tmp/flutter-sdk";
  final dir = "$root/bin/cache/artifacts/material_fonts";
  Future<void> load(String family, List<String> paths) async {
    final l = FontLoader(family);
    for (final f in paths) {
      final b = File(f).readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }

  // The app's own font (bundled in assets/fonts).
  await load("Sora", [
    "assets/fonts/Sora-400.ttf",
    "assets/fonts/Sora-600.ttf",
    "assets/fonts/Sora-700.ttf",
  ]);
  if (!Directory(dir).existsSync()) {
    return; // other machines: icons fall back to the test font
  }
  await load("Roboto", [
    "$dir/Roboto-Regular.ttf",
    "$dir/Roboto-Medium.ttf",
    "$dir/Roboto-Bold.ttf",
    "$dir/Roboto-Black.ttf"
  ]);
  await load("MaterialIcons", ["$dir/MaterialIcons-Regular.otf"]);
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
  List<Subscription> subs = const [],
  Future<void> Function(WidgetTester)? then,
}) async {
  t.view.physicalSize = const Size(900, 1950);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(
      {"theme_v1": mode == ThemeMode.light ? "light" : "dark"});

  final container = ProviderContainer(overrides: [
    configsProvider.overrideWith(() => _FakeConfigs(configs)),
    subscriptionsProvider.overrideWith(() => _FakeSubs(subs)),
    tunnelStateProvider.overrideWith((ref) => Stream.value(tunnel)),
    identityStoreProvider.overrideWithValue(IdentityStore(vault: _MemVault())),
    onboardedProvider.overrideWith((ref) async => onboarded),
    if (connectedTimer) connectedSinceProvider.overrideWith(_FakeSince.new),
    exitInfoProvider.overrideWith((ref) async => tunnel.phase ==
            TunnelPhase.connected
        ? const ExitInfo("203.0.113.7", country: "Germany", countryCode: "DE")
        : null),
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
    expect(find.textContaining("203.0.113.7"), findsWidgets);
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

  testWidgets("add sheet", (t) async {
    await _show(t, shot: "add_sheet_dark", configs: _samples, selected: "1",
        then: (t) async {
      await t.tap(find.widgetWithText(FilledButton, "Add"));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
    expect(find.text("Paste from clipboard"), findsOneWidget);
    expect(find.text("Scan a QR code"), findsOneWidget);
    expect(find.text("Create manually"), findsOneWidget);
    expect(find.text("Add a subscription"), findsOneWidget);
  });

  testWidgets("empty home has an Add button", (t) async {
    await _show(t, shot: "home_empty_light", mode: ThemeMode.light);
    expect(find.text("Add a config"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, "Add"), findsOneWidget);
  });

  testWidgets("config actions sheet", (t) async {
    await _show(t,
        shot: "config_actions_dark",
        configs: _samples,
        selected: "1", then: (t) async {
      await t.tap(find.byIcon(Icons.more_horiz_rounded).first);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
    expect(find.text("Edit"), findsOneWidget);
    expect(find.text("Delete"), findsOneWidget);
  });

  Future<void> pushScreen(WidgetTester t, Widget w) async {
    final ctx = t.element(find.byType(Scaffold).first);
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => w));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  const fullLink =
      "vless://11111111-2222-3333-4444-555555555555@fra.example.com:443?encryption=none&security=tls&sni=fra.example.com&type=ws&path=%2Fws&host=cdn.example.com#Frankfurt";

  testWidgets("config editor — new", (t) async {
    await _show(t, shot: "editor_new_dark", configs: _samples, then: (t) async {
      await pushScreen(t, const ConfigEditorScreen());
    });
    expect(find.text("New config"), findsOneWidget);
    expect(find.text("Add config"), findsOneWidget);
  });

  testWidgets("config editor — new, light, shows errors", (t) async {
    await _show(t,
        shot: "editor_errors_light",
        mode: ThemeMode.light,
        configs: _samples, then: (t) async {
      await pushScreen(t, const ConfigEditorScreen());
      await t.ensureVisible(find.text("Add config"));
      await t.tap(find.text("Add config"));
      await t.pump(const Duration(milliseconds: 300));
    });
    expect(find.text("Enter the server address"), findsOneWidget);
  });

  testWidgets("config editor — edit", (t) async {
    const c = VpnConfig(
        id: "e1",
        name: "Frankfurt",
        protocol: VpnProtocol.vless,
        host: "fra.example.com",
        port: 443,
        raw: fullLink,
        source: "manual");
    await _show(t, shot: "editor_edit_dark", configs: [c], then: (t) async {
      await pushScreen(t, const ConfigEditorScreen(existing: c));
    });
    expect(find.text("Edit config"), findsOneWidget);
    expect(find.text("Save changes"), findsOneWidget);
    expect(find.text("fra.example.com"), findsWidgets);
  });

  testWidgets("subscriptions — empty", (t) async {
    await _show(t, shot: "subs_empty_dark", configs: _samples, then: (t) async {
      await pushScreen(t, const SubscriptionsScreen());
    });
    expect(find.text("No subscriptions"), findsOneWidget);
  });

  testWidgets("subscriptions — list", (t) async {
    final subs = [
      Subscription(
          id: "s1",
          name: "Vipnet daily",
          url: "https://example.com/sub?token=abc",
          updatedAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 12)),
          count: 24),
      const Subscription(
          id: "s2",
          name: "Backup list",
          url: "https://backup.example.org/s",
          count: 6,
          error: "The server took too long"),
    ];
    await _show(t, shot: "subs_list_dark", configs: _samples, subs: subs,
        then: (t) async {
      await pushScreen(t, const SubscriptionsScreen());
    });
    expect(find.text("Vipnet daily"), findsOneWidget);
    expect(find.text("The server took too long"), findsOneWidget);
    expect(find.textContaining("example.com/sub"), findsNothing,
        reason: "the subscription URL (it may hold a token) must not be shown");
  });

  testWidgets("settings", (t) async {
    await _show(t, shot: "settings_dark", tab: 1);
    expect(find.text("Kill switch"), findsOneWidget);
  });

  testWidgets("settings (light)", (t) async {
    await _show(t, shot: "settings_light", tab: 1, mode: ThemeMode.light);
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

  const sampleLine =
      "0123456789abcdef0123456789abcdef 3FA9-0C21-B7D4-9E10 Channel_gift";

  testWidgets("gate line dialog", (t) async {
    await _show(t, shot: "gate_dialog_dark", configs: _samples, selected: "1",
        then: (t) async {
      final ctx = t.element(find.byType(Scaffold).first);
      showGateLineDialog(ctx, sampleLine);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
    expect(find.text("Allow this lock on your server"), findsOneWidget);
    expect(find.text("Copy line"), findsOneWidget);
    await t.tap(find.text("Copy line"));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text("Copied"), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets("gate allow-list screen", (t) async {
    await _show(t, shot: "gate_allowlist_dark", configs: _samples,
        then: (t) async {
      final ctx = t.element(find.byType(Scaffold).first);
      Navigator.of(ctx).push(
          MaterialPageRoute<void>(builder: (_) => const GateAllowListScreen()));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    });
  });
}
