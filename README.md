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
- **Locked-config system** (`lib/domain/locked_config_codec.dart`, spec in `docs/LOCK_V3.md`): a
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

- `LOCK_P1`, `LOCK_P2`, `LOCK_P3`, `LOCK_P4` — four random strings (e.g. 16+ chars
  each) that together form the lock secret. They are injected via `--dart-define`,
  XOR-masked and rejoined at runtime; never committed. Without them a build cannot
  lock or open `.ovsea` files.
- `AD_INTERSTITIAL_ID` (optional) — AdMob interstitial unit shown after connect.
  `ADMOB_APP_ID` (optional) — AdMob application id for the manifest. Both default
  to Google's public *test* ids, so unconfigured builds never serve real ads.

Rotate the four parts (and bump `LockedConfigCodec.keyGeneration`) every release.

## Why browsing this repo does not break the lock

The locked-config key is **not in the source**. `LockedConfigCodec` reads it from
a compile-time define (`LOCK_P1..P4`) that only exists during a CI build. A
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


## Releases (installable APK)

GitHub Actions *artifacts are ZIP files* — Android cannot install a zip. To get a
directly installable `.apk`, use a Release:

```
git tag v1.0
git push origin v1.0
```

The `Release` workflow builds a signed APK and publishes it as a GitHub Release
asset (raw `.apk`, downloadable and installable directly), plus a Windows zip.

### Signing secrets (for stable, Play-ready signing)

Add these repo secrets so every build is signed with the same release key
(required for app updates and Play). If they are absent, CI falls back to a
throwaway key so the APK still installs for testing.

- `ANDROID_KEYSTORE_BASE64` — base64 of your release keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## Structure

```
lib/
  main.dart, app.dart, providers.dart   entry, MaterialApp (fa/en, light/dark), Riverpod
  core/                                  app_config (flavors), log (redacting), strings (fa/en),
                                         http_client (Dio + SPKI pinning + bounded retry)
  domain/                                vpn_config, config_parser, locked_config_codec (v3)
  data/                                  config_store (Keystore storage + v1→v2 migration), ad_service
  features/{shell,configs,add}/          UI
android/                                 committed native project (R8, FLAG_SECURE, AdMob placeholder)
docs/                                    ANDROID_PLAN, LOCK_V3, LOCK_OFFLINE, THREAT_MODEL
test/                                    codec, parser, store migration, SPKI pin, i18n, log
server/                                  Go feed/owner backend (not used by the lock any more)
```

Build flags: `--dart-define=FLAVOR=dev|staging|prod`, `API_BASE_URL`, `TLS_PINS`
(comma-separated base64 SHA-256 SPKI pins; prod refuses to build a client without them).

Checks (also run by `.github/workflows/ci.yml`):

```
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --dart-define=LOCK_P1=... (any 4 strings)
```
