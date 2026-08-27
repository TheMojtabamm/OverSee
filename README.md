# Oversea

Oversea — cross-platform tunnel client (Android + Windows for now). Flutter front end;
native tunnel engines are added in a later phase.

This repository is **code-only** and compiles on GitHub Actions — you do not need
a local Flutter install to produce builds.

## What this phase includes

- Config model + parser for common formats (VLESS, VMess, Trojan, Shadowsocks,
  SOCKS, HTTP; OpenVPN / IKEv2 / L2TP are stored and managed, tunneling comes
  later).
- Add configs by paste or by subscription URL.
- Local on-device storage (no account, no server needed to use the app).
- **Locked-config system** (`lib/services/locked_config_codec.dart`): a
  time-rotating, key-injected format so configs can only be opened by this app.
- **Free-config feed** client (`lib/services/free_configs_service.dart`): an
  in-app list of channels and their configs, served from your own feed server.
- CI that builds a signed-ready APK/AAB and a Windows release.

## What is NOT here yet (next phase)

- The native tunnel engines (Xray-core, OpenVPN, strongSwan) inside a
  platform `VpnService`. This is the largest piece and is added incrementally.
- Real "Connect" — currently the connect button only signals the engine is not
  wired yet.

## Build

Push to `main` (or run the workflow manually). Artifacts:

- `Android build` → `app-release.apk` and `app-release.aab`
- `Windows build` → `oversea-windows.zip`

### Required repository secret

Add one secret in **Settings → Secrets and variables → Actions**:

- `LOCK_CLIENT_KEY` — the client-side key material for the locked-config system.
  It must match the key held by your server-side config generator.

The build injects it via `--dart-define`; it is never committed.

## Why browsing this repo does not break the lock

The locked-config key is **not in the source**. `LockedConfigCodec` reads it from
a compile-time define (`LOCK_CLIENT_KEY`) that only exists during a CI build. A
fresh checkout carries an empty value, so the public source shows the algorithm
but no key — and the algorithm alone opens nothing.

Layers:

1. **No secret in the repo** — injected at build time from a CI secret.
2. **Time-rotating key** — the AES key is derived per date-based epoch, so a key
   pulled from one build stops working after the rotation period.
3. **Obfuscated release binary** — Android builds use `--obfuscate`.
4. **Hybrid server component (recommended)** — when enabled, part of the key
   comes from your server per epoch, so even a fully reversed binary cannot
   derive keys offline; it must reach an endpoint you rate-limit and monitor.

Honest note: no client-side lock on an open platform is unbreakable. The goal is
to make breaking it expensive enough that it is not worth it in practice.

## Google Play notes (for the later phase)

When the tunnel engine is added, Play requires: a `VpnService` implementation, a
declared foreground service of type `specialUse`/`systemExempted` as applicable,
a published privacy policy, target of a recent API level, and clear disclosure of
what the VPN does. Keep these in mind before the first store submission.

## Battery usage (design principle for the engine phase)

Battery drain is a common weakness in this category. When adding the engine:

- Use a single efficient native core; avoid busy-polling and tight timers.
- Respect Doze / app-standby; use reasonable keepalive intervals, not aggressive ones.
- Run one properly-configured foreground service, not multiple wakelocks.
- Prefer kernel-assisted paths where available over user-space copying.

## Structure

```
lib/
  models/vpn_config.dart          config model + protocol enum
  services/
    config_parser.dart            parse standard config URIs
    subscription_service.dart     import from a subscription URL
    free_configs_service.dart     in-app free-config feed client
    locked_config_codec.dart      locked-config encrypt/decrypt (rotating key)
    config_store.dart             local persistence
  main.dart                       minimal functional UI
.github/workflows/                Android + Windows CI
```
