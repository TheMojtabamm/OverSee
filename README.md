# Oversea

An Android VPN client (Flutter + Xray-core) with **locked config files**, plus a small
server tool, `oversee`, that makes a decoded config useless to anyone but the app.

- **App** (`lib/`, `android/`): import Xray links, connect through a VpnService tunnel,
  create and share locked `.ovsea` files, AdMob ads. The UI is English only.
- **Server tool** (`server/`): the `oversee` gate manager with a terminal UI.
- **Docs** (`docs/`): design, threat model, setup and test plans.

Status: it compiles, and unit tests, Xray-config validation and end-to-end tests against a
real Xray and the real gate pass in CI. **It has not been run on a real phone, a real VPS
or a real Cloudflare/Fastly account yet** — see `docs/DEVICE_TEST_PLAN.md`.

## How the lock works (short version)

1. A locked `.ovsea` file is encrypted (AES-256-GCM). Its key is derived inside a native
   library (`libovs.so`) from secrets that are masked per build, and from a check that the
   APK is the genuine, unmodified, un-hooked app. A bot that only has the file can't read it.
2. Each file also carries a random *gate code* and the creator's signature. The app sends a
   daily token derived from them in an `X-Oversea-Auth` header. The creator's server only
   lets through tokens for codes on its allow-list.
3. So even if someone decodes the plain config (a bot, Frida, a re-lock under another
   name), it **does not connect**: there is no valid header. Revoking a code on the server
   cuts off that file for everyone, including the real app.

Limits, honestly: the app opens files offline, so a skilled reverse engineer can extract the
secrets from a build (each build and release makes that costlier, it does not make it
impossible). The gate needs the transport to carry a header (WebSocket / HTTPUpgrade, also
through Cloudflare/Fastly); Reality over plain TCP can't be gated. Details:
`docs/THREAT_MODEL.md`, `docs/LOCK_V3.md`, `docs/GATE.md`.

## Server: install and update (one line)

On a Linux server (amd64 or arm64), as root:

```bash
curl -fsSL https://github.com/themojtabamm/OverSee/releases/download/server-latest/install.sh | sudo bash
```

Run the same line again any time to **update to the newest build** (the running gate is
restarted). Then run `sudo oversee` to open the manager (Status / Locks / Keys / Setup / Logs).
Pin a version with `OVERSEE_VERSION=server-v1.2.3`; remove with `… | sudo bash -s -- --uninstall`.

The installer needs the repository's releases to be public. `server-latest` is rebuilt by
`.github/workflows/server-release.yml` on every push to `main` that changes `server/`
(or run that workflow manually).

Useful commands: `oversee doctor` (finds holes that make the lock pointless, e.g. Xray
reachable around the gate), `oversee cdn-test` (does the header survive your CDN),
`oversee add / revoke / list`. Full guide: `docs/GATE.md`.

## App: build

Builds run on GitHub Actions; no local Flutter needed.

- **Test build:** *Actions → Release → Run workflow* on any branch (keep "test build" on).
  It produces a signed APK as a downloadable artifact (kept 14 days). It uses Google's test
  ads and doesn't need AdMob IDs.
- **Real release:** push a tag `v1.0`; the workflow builds the signed APK and publishes it as a
  GitHub Release (plus a Windows zip). It **refuses to build** without real AdMob IDs.

### Repository secrets (Settings → Secrets and variables → Actions)

| Secret | Purpose |
|---|---|
| `LOCK_P1` … `LOCK_P4` | four random strings (16+ chars each) that form the file-lock secret; never committed, masked per build |
| `GATE_KEY` | the app key for the server gate; add the same value on the server (`oversee key add`) |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | release signing key (without them a throwaway key is used: fine for testing, not for updates or Play) |
| `PLAY_CERT_SHA256` | after the first Play upload: the app-signing certificate SHA-256 (hex, no colons), so Play installs derive the right keys |
| `ADMOB_APP_ID`, `AD_INTERSTITIAL_ID`, `AD_BANNER_ID` | your AdMob IDs (`docs/ADMOB_SETUP.md`); revenue goes to the account that owns them |

Without `LOCK_P*` / `GATE_KEY` the app still builds but cannot open locked files (it fails
closed). Rotate the secrets for every release.

## Develop

```
flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --dart-define=LOCK_P1=aaaaaaaaaaaaaaaa --dart-define=LOCK_P2=bbbbbbbbbbbbbbbb \
             --dart-define=LOCK_P3=cccccccccccccccc --dart-define=LOCK_P4=dddddddddddddddd \
             --dart-define=GATE_KEY=gate-dev-key
(cd server && go vet ./... && go test ./...)
```

`ci.yml` also runs the native C++ tests (ASan/UBSan), native-equals-Dart checks, validation of
every generated Xray config with real Xray-core, and the end-to-end scripts in `tool/`
(`e2e_gate.sh`, `e2e_cdn.sh`, `e2e_lockflow.sh`). The Xray engine is built from a pinned
source version (`tool/build_xray_aar.sh`); nothing prebuilt is downloaded.

## Layout

```
lib/        core/ domain/ data/ features/ ui/   Flutter app (Riverpod)
android/    VpnService, Xray bridge, native lock core (cpp/), manifest
server/     Go module: internal/gate (the gate), internal/oversee + internal/tui, cmd/oversee, install.sh
tool/       Xray build, config validation, secret masking/verification, e2e scripts
test/       Dart tests (codec, gate token, tamper, importer, UI smoke screenshots → build/shots)
docs/       ANDROID_PLAN, LOCK_V3, LOCK_OFFLINE, THREAT_MODEL, GATE, PLAY_COMPLIANCE,
            PRIVACY_POLICY, ADMOB_SETUP, DEVICE_TEST_PLAN
```

Google Play: see `docs/PLAY_COMPLIANCE.md` (VPN disclosure before the system prompt,
foreground-service declaration, UMP consent, Data safety) and `docs/PRIVACY_POLICY.md`.
