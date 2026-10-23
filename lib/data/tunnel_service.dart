import "package:flutter/services.dart";

import "../domain/tunnel_settings.dart";

enum TunnelPhase { disconnected, connecting, connected, blocked, error }

class TunnelState {
  final TunnelPhase phase;
  final String? message;
  final int up;
  final int down;
  final int upRate;
  final int downRate;

  const TunnelState(this.phase,
      {this.message,
      this.up = 0,
      this.down = 0,
      this.upRate = 0,
      this.downRate = 0});

  static const idle = TunnelState(TunnelPhase.disconnected);

  factory TunnelState.fromMap(Map<Object?, Object?> m) => TunnelState(
        TunnelPhase.values.firstWhere((p) => p.name == m["state"],
            orElse: () => TunnelPhase.disconnected),
        message: m["message"] as String?,
        up: (m["up"] as num?)?.toInt() ?? 0,
        down: (m["down"] as num?)?.toInt() ?? 0,
        upRate: (m["upRate"] as num?)?.toInt() ?? 0,
        downRate: (m["downRate"] as num?)?.toInt() ?? 0,
      );
}

class InstalledApp {
  final String package;
  final String label;
  const InstalledApp(this.package, this.label);
}

/// Thin wrapper over the native VpnService channel. Every call degrades to a safe
/// default when the native side is missing (tests, desktop builds).
class TunnelService {
  static const _m = MethodChannel("oversea/tunnel");
  static const _e = EventChannel("oversea/tunnel/events");

  Stream<TunnelState> get states => _e
      .receiveBroadcastStream()
      .map((e) => TunnelState.fromMap(e as Map<Object?, Object?>))
      .handleError((_) {});

  Future<bool> prepare() => _bool("prepare");
  Future<bool> requestNotifications() => _bool("requestNotifications");

  Future<void> start({
    required String configJson,
    required String label,
    required TunnelSettings settings,
  }) =>
      _m.invokeMethod<void>("start", {
        "config": configJson,
        "label": label,
        "mode": settings.splitMode.name,
        "apps": settings.apps,
        "ipv6": settings.ipv6,
        "mtu": 1500,
        "killSwitch": settings.killSwitch,
      });

  Future<void> stop() async {
    try {
      await _m.invokeMethod<void>("stop");
    } on MissingPluginException {
      // no native side
    }
  }

  /// Round-trip through the config's outbound in ms, or -1 on failure/timeout.
  Future<int> testDelay(String configJson,
      {String url = "https://www.google.com/generate_204"}) async {
    try {
      return (await _m.invokeMethod<num>(
                  "testDelay", {"config": configJson, "url": url}))
              ?.toInt() ??
          -1;
    } on MissingPluginException {
      return -1;
    } on PlatformException {
      return -1;
    }
  }

  Future<TunnelState> status() async {
    try {
      final m = await _m.invokeMethod<Map<Object?, Object?>>("status");
      return m == null ? TunnelState.idle : TunnelState.fromMap(m);
    } on MissingPluginException {
      return TunnelState.idle;
    }
  }

  Future<List<InstalledApp>> listApps() async {
    try {
      final l = await _m.invokeListMethod<Map<Object?, Object?>>("listApps");
      return (l ?? const [])
          .map((m) => InstalledApp("${m["package"]}", "${m["label"]}"))
          .toList();
    } on MissingPluginException {
      return const [];
    }
  }

  Future<void> openVpnSettings() async {
    try {
      await _m.invokeMethod<void>("openVpnSettings");
    } on MissingPluginException {
      // no native side
    }
  }

  Future<bool> _bool(String method) async {
    try {
      return await _m.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
