import "dart:convert";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:oversea/data/config_store.dart";
import "package:oversea/data/subscription_service.dart";
import "package:oversea/data/subscription_store.dart";
import "package:oversea/domain/subscription.dart";
import "package:oversea/domain/vpn_config.dart";
import "package:oversea/providers.dart";

class _MemVault implements Vault {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

class _NoLegacy implements LegacyStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> clear() async {}
}

const _a =
    "vless://11111111-2222-3333-4444-555555555555@a.example.com:443?encryption=none&security=tls&sni=a.example.com&type=ws&path=%2Fx#A";
const _b = "trojan://pw@b.example.com:443?security=tls&sni=b.example.com#B";
const _c = "ss://YWVzLTI1Ni1nY206c2VjcmV0@c.example.com:8388#C";

void main() {
  group("parseBody", () {
    test("plain lines", () {
      final l = Subscription.parseBody("$_a\n$_b\n", subId: "s1");
      expect(l.map((c) => c.name), ["A", "B"]);
      expect(l.every((c) => c.channelRef == "s1"), isTrue);
    });

    test("base64 of lines, standard and url-safe", () {
      final std = base64.encode(utf8.encode("$_a\n$_b"));
      expect(Subscription.parseBody(std, subId: "s").length, 2);
      final safe =
          base64Url.encode(utf8.encode("$_a\n$_b\n$_c")).replaceAll("=", "");
      expect(Subscription.parseBody(safe, subId: "s").length, 3);
    });

    test("junk and unsupported protocols give nothing", () {
      expect(Subscription.parseBody("hello world", subId: "s"), isEmpty);
      expect(Subscription.parseBody("", subId: "s"), isEmpty);
      expect(
          Subscription.parseBody("socks5://u@h:1080#x", subId: "s"), isEmpty);
    });
  });

  group("merge", () {
    VpnConfig cfg(String id, String raw, {String? sub}) => VpnConfig(
        id: id,
        name: id,
        protocol: VpnProtocol.vless,
        raw: raw,
        source: "x",
        channelRef: sub);

    test("keeps ids of surviving configs, drops vanished ones, adds new", () {
      final current = [
        cfg("manual", "vless://m", sub: null),
        cfg("old1", "vless://1", sub: "s"),
        cfg("old2", "vless://2", sub: "s"),
      ];
      final fetched = [
        cfg("n1", "vless://1", sub: "s"),
        cfg("n3", "vless://3", sub: "s")
      ];
      final out =
          Subscription.merge(current: current, subId: "s", fetched: fetched);
      expect(out.map((c) => c.id), ["manual", "old1", "n3"]);
    });

    test("does not duplicate a link the user added by hand", () {
      final out = Subscription.merge(
          current: [cfg("hand", "vless://1")],
          subId: "s",
          fetched: [cfg("n1", "vless://1", sub: "s")]);
      expect(out.map((c) => c.id), ["hand"]);
    });
  });

  group("provider", () {
    late _MemVault vault;
    late String body;
    Object? failWith;

    ProviderContainer make() {
      vault = _MemVault();
      return ProviderContainer(overrides: [
        configStoreProvider
            .overrideWithValue(ConfigStore(vault: vault, legacy: _NoLegacy())),
        subscriptionStoreProvider
            .overrideWithValue(SubscriptionStore(vault: vault)),
        subscriptionServiceProvider
            .overrideWithValue(SubscriptionService(fetcher: (u) async {
          if (failWith != null) throw failWith!;
          return body;
        })),
      ]);
    }

    setUp(() {
      body = "$_a\n$_b";
      failWith = null;
    });

    test(
        "add fetches, stores and tags the configs; refresh updates; remove cleans up",
        () async {
      final c = make();
      addTearDown(c.dispose);
      await c.read(configsProvider.future);
      final subs = c.read(subscriptionsProvider.notifier);
      await c.read(subscriptionsProvider.future);

      final r =
          await subs.add("https://example.com/sub?token=abc", name: "My sub");
      expect(r.ok, isTrue);
      expect(r.count, 2);
      expect(c.read(configsProvider).value!.length, 2);
      final sub = c.read(subscriptionsProvider).value!.single;
      expect(sub.name, "My sub");
      expect(sub.count, 2);

      // The list changed on the server: B is gone, C is new.
      body = "$_a\n$_c";
      expect((await subs.refresh(sub.id)).count, 2);
      expect(c.read(configsProvider).value!.map((x) => x.name).toSet(),
          {"A", "C"});

      await subs.remove(sub.id);
      expect(c.read(configsProvider).value, isEmpty);
      expect(c.read(subscriptionsProvider).value, isEmpty);
    });

    test("a failing refresh keeps the old configs and records a safe error",
        () async {
      final c = make();
      addTearDown(c.dispose);
      await c.read(configsProvider.future);
      final subs = c.read(subscriptionsProvider.notifier);
      await c.read(subscriptionsProvider.future);
      await subs.add("https://example.com/sub", name: "S");
      final id = c.read(subscriptionsProvider).value!.single.id;

      failWith = const SubscriptionFetchException("The server took too long");
      final r = await subs.refresh(id);
      expect(r.ok, isFalse);
      expect(c.read(configsProvider).value!.length, 2);
      final s = c.read(subscriptionsProvider).value!.single;
      expect(s.error, "The server took too long");
      expect(s.error, isNot(contains("example.com")));
    });

    test("bad URLs, duplicates and empty lists are refused", () async {
      final c = make();
      addTearDown(c.dispose);
      await c.read(configsProvider.future);
      final subs = c.read(subscriptionsProvider.notifier);
      await c.read(subscriptionsProvider.future);

      expect((await subs.add("not a url")).ok, isFalse);
      expect((await subs.add("ftp://example.com/x")).ok, isFalse);
      body = "nothing useful here";
      expect((await subs.add("https://example.com/empty")).ok, isFalse);
      expect(c.read(subscriptionsProvider).value, isEmpty);

      body = _a;
      expect((await subs.add("https://example.com/ok")).ok, isTrue);
      expect((await subs.add("https://example.com/ok")).ok, isFalse);
    });
  });
}
