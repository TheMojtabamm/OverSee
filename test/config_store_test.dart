import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:oversea/data/config_store.dart";
import "package:oversea/domain/vpn_config.dart";

class MemVault implements Vault {
  final m = <String, String>{};
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
  @override
  Future<void> delete(String k) async => m.remove(k);
}

class MemLegacy implements LegacyStore {
  String? data;
  MemLegacy(this.data);
  @override
  Future<String?> read() async => data;
  @override
  Future<void> clear() async => data = null;
}

VpnConfig cfg(String id, String raw,
        {String? ad, String? tg, bool locked = false}) =>
    VpnConfig(
      id: id,
      name: id,
      protocol: VpnProtocol.vless,
      host: "h.com",
      port: 443,
      raw: raw,
      source: "manual",
      adText: ad,
      telegramUrl: tg,
      locked: locked,
    );

void main() {
  test("legacy plaintext is migrated, wiped, and locked imports re-flagged",
      () async {
    final legacy = MemLegacy(jsonEncode([
      cfg("plain", "vless://a@h:1#plain").toJson(),
      cfg("fromLockedFile", "vless://b@h:1#x", ad: "ad", tg: "https://t.me/x")
          .toJson(),
      cfg("oldOwnerTab", "locked:AAAA").toJson(),
    ]));
    final vault = MemVault();
    final store = ConfigStore(vault: vault, legacy: legacy);

    final out = await store.load();
    expect(
        out.map((c) => c.id), ["plain", "fromLockedFile"]); // v1 blob dropped
    expect(out[0].locked, isFalse);
    expect(out[1].locked, isTrue);
    expect(out[1].host, isNull); // server hidden after migration
    expect(legacy.data, isNull); // plaintext copy wiped
    expect(vault.m[ConfigStore.schemaKey], "2");
  });

  test("migration runs once and is idempotent", () async {
    final legacy = MemLegacy(jsonEncode([cfg("a", "vless://a@h:1").toJson()]));
    final store = ConfigStore(vault: MemVault(), legacy: legacy);
    await store.load();
    legacy.data =
        jsonEncode([cfg("zzz", "vless://z@h:1").toJson()]); // must be ignored
    expect((await store.load()).map((c) => c.id), ["a"]);
  });

  test("add de-dupes by raw and remove works", () async {
    final store = ConfigStore(vault: MemVault(), legacy: MemLegacy(null));
    await store.add([cfg("1", "vless://a@h:1")]);
    await store.add([cfg("2", "vless://a@h:1"), cfg("3", "vless://b@h:1")]);
    expect((await store.load()).map((c) => c.id), ["1", "3"]);
    await store.remove("1");
    expect((await store.load()).map((c) => c.id), ["3"]);
  });
}
