# Oversea — UI handoff (what the interface must connect to)

For whoever redesigns the UI. The app is **Flutter + Riverpod, Android only, English UI only**.
All logic already exists; a new UI only has to *call* the pieces below. Do not re-implement
parsing, locking, tunnel or gate logic in widgets.

Entry points: `lib/main.dart` → `lib/app.dart` → `lib/features/shell/root_shell.dart`
(3 bottom tabs: Home, Add, Settings). Theme/tokens: `lib/ui/theme.dart`, shared widgets
`lib/ui/widgets.dart`, big button `lib/ui/connect_button.dart`. All user-visible text lives in
`lib/core/strings.dart` (`S.of(context).t("key")`); add keys there, never hard-code.

## 1. Hard rules (security / policy — the UI must keep these)

1. **A locked config is never shown, copied, shared as text, or turned into a QR.** Check
   `VpnConfig.locked`. Show only name, protocol, "Locked", creator, expiry. Never print `raw`,
   `host`, `port` for locked configs (Diagnostics already follows this).
2. **VPN disclosure before the system VPN prompt** (Play policy). Keep the flow in
   `connect_flow.dart` (`SettingsStore.disclosureAccepted/acceptDisclosure`, strings `disclosure_*`).
3. **Ads:** interstitial only *after* the tunnel is up, never at launch/exit/while connecting,
   ≥5 min apart, none on the very first connect (`AdService.mayShow`). Banner only after consent
   (`BannerAdBox`). Owner ad text from locked files is shown labelled **Sponsored** with a
   Continue button (`_showSponsored`).
4. **Unencrypted configs** (`XrayConfigBuilder.isUnencrypted(raw)`) get a visible "Not encrypted" badge.
5. Don't expose raw error text from the core (it may contain config parts).
6. Creator trust: unsigned / unknown-creator locked files must be visibly different from a trusted one.

## 2. Screens and the backend each one needs

### Onboarding (`features/onboarding`)
3 intro pages (`ob1..ob3_*`) → `SettingsStore.setOnboarded()`. Gate: `onboardedProvider`.

### Home
Needs:
- `tunnelStateProvider` → `TunnelState{phase, message, up, down, upRate, downRate}`;
  `TunnelPhase = disconnected | connecting | connected | blocked | error`.
  (`blocked` = kill-switch hold; `error.message` is safe to show.)
- `selectedConfigProvider` (VpnConfig?) + `selectedConfigIdProvider.select(id)`; list from `configsProvider`.
- `connectedSinceProvider` → DateTime? for the session timer.
- `exitInfoProvider` → `ExitInfo{ip, country, countryCode, label}` (null while not connected/unavailable).
- `activeConfigProvider` (what the running tunnel was started with).
- `pingProvider` Map<id, ms> (absent = untested, -1 failed, -2 testing); `testPing(ref, cfg)`, `testAllPings(ref, list)`.
- **Connect / disconnect button:** `toggleConnection(context, ref)` in `connect_flow.dart` — it handles
  disclosure, VPN permission, notification permission, expiry, gate token, sponsored ad, ad after connect.
  Call it; don't call `TunnelService.start` directly.
- `reconnectIfStale(context, ref)` — a gated tunnel running past its token day must restart.
- Per-config row data: name, `protocol.label`, `locked`, `gated`, `creator`, `isExpired()`, `expiresAt`,
  `source`, host/port (**unlocked only**), unencrypted badge.
- Row actions: select, ping, share (`showShareSheet`), delete (`configsProvider.remove(id)`).
- Ad slot: `BannerAdBox` (zero height until loaded).

### Add (`features/add`)
- Paste: read clipboard → `Importer.fromText(text)` → `ImportOutcome{configs, errorKey, skipped, isOk}`.
- File: pick `.ovsea`/text file → same `Importer.fromText`.
- Then `configsProvider.addAll(outcome.configs)`; show `errorKey` via strings (`clipboard_empty`,
  `import_too_big`, `no_xray`, `no_key`, `import_invalid`).
- "Open with Oversea": Android intent → `IncomingService.listen(onText)` (root_shell shows a confirm
  dialog `incoming_*`, then imports).
- Locked files may carry owner ad text + a Telegram link (shown as Sponsored on connect).

### Share / Lock sheet (`features/configs/share_sheet.dart` → `showShareSheet(context, cfg)`)
Plain share (copy / QR / `Share.share`) **or** Lock:
- inputs: ad text (≤200), Telegram URL (`AdContent.channelUrl`), expiry (24h/7d/30d/never), Gate switch
  (only if `GateToken.available && XrayConfigBuilder.supportsGate(raw)`).
- output: writes a real `oversea_<ms>.ovsea` file and shares it; with Gate on, first shows the **gate line**
  (`showGateLineDialog` / `GateLineCard`) — the creator must add it on the server
  (`sudo oversee add "<line>"`); the sheet saves it via `IdentityStore.addGateLine`.
- Lock uses `LockedConfigCodec.encode(...)`, `IdentityStore.load()` (creator identity),
  `GateToken.newCode()`, `GateToken.allowListLine(code, fingerprint, note)`.

### Settings (`features/settings`)
`settingsProvider` (AsyncNotifier<TunnelSettings>) with `.change((s) => s.copyWith(...))`. Fields:
| Field | Type | Meaning |
|---|---|---|
| `dns` | `DnsPreset` tunnel(default, "Off (plain DNS)") / cloudflare / google / quad9 (DoH) |
| `fragment` | bool | TLS fragment (anti-DPI) |
| `ipv6` | bool | route IPv6 |
| `bypassLan` | bool | LAN direct |
| `killSwitch` | bool | block traffic when tunnel drops |
| `splitMode` | `SplitMode` all / allow / deny | per-app routing |
| `apps` | List<String> packages | used with allow/deny; picker: `TunnelService.listApps()` → `InstalledApp{package,label}` |

Other rows: theme (`themeModeProvider.set(ThemeMode)`), trusted creators (`trustedCreatorsProvider.setTrusted(fp, bool)`),
**Gate allow-list** screen (`IdentityStore.gateLines()`, copy line / copy command), **Diagnostics** screen,
ad privacy options (`AdService.privacyOptionsRequired()` / `showPrivacyOptions()`), privacy policy link
(`AppConfig`), VPN system settings (`TunnelService.openVpnSettings()`), version (`AppConfig.version`).

### Diagnostics (`settings/diagnostics_screen.dart`)
Run tests for the selected config: TCP reach, WebSocket/httpupgrade probe (with the real gate token when gated),
integrity line (`LockedConfigCodec.environmentTag.isEmpty`), core log tail (unlocked only). Keep results-only for locked.

## 3. Backend surface (what to call)

| Area | API |
|---|---|
| Config store | `configsProvider` (list, `addAll`, `remove`, `reload`) — encrypted vault, secure storage |
| Import | `Importer.fromText` · `ConfigParser.parseMany` |
| Lock / unlock | `LockedConfigCodec.encode/decodeConfig/looksLocked/hasKey` |
| Gate token | `GateToken.available`, `.current(code, creatorFp)`, `.newCode()`, `.allowListLine(...)` |
| Tunnel | `tunnelStateProvider`, `toggleConnection`, `TunnelService.{prepare,requestNotifications,start,stop,status,testDelay,listApps,openVpnSettings}` |
| Xray config | `XrayConfigBuilder.build(raw, TunnelOptions)`, `.isUnencrypted(raw)`, `.supportsGate(raw)` |
| Exit IP | `exitInfoProvider` (needs `probeProvider`, set by the connect flow) |
| Ads | `AdService.init/preload/mayShow/showAfterConnect/privacyOptionsRequired/showPrivacyOptions`, `BannerAdBox` |
| Settings | `SettingsStore`: theme, selected config, onboarded, disclosure, first-connect, trusted creators |
| Integrity | `IntegrityService.init()` at startup (sets the environment tag; never block startup) |

Native channels (already implemented, don't change signatures): MethodChannel `oversea/tunnel`
(prepare, requestNotifications, start, stop, status, testDelay, listApps, openVpnSettings, integrity),
EventChannel `oversea/tunnel/events` (one shared stream — use `TunnelService.states`, never open another),
MethodChannel `oversea/incoming`.

## 4. Data shapes

`VpnConfig`: `id, name, protocol(VpnProtocol: vless|vmess|trojan|shadowsocks|…), host?, port?, raw, source,
channelRef?, adText?, telegramUrl?, locked, creator?, gateCode?, expiresAt?` + `gated`, `isExpired()`.
`TunnelState`: see Home. `ExitInfo`: `ip, country?, countryCode?, label`. `ImportOutcome`: see Add.
Traffic numbers are bytes and bytes/second (`up/down`, `upRate/downRate`) — format in the UI.

## 5. States every screen must handle

Empty (no configs), loading (`AsyncValue.loading`), error (`AsyncValue.error`), connecting, connected,
blocked (kill switch), error with message, expired locked config (cannot connect: show why), missing app
key (`no_key`), long names/hosts (ellipsis — a past overflow bug), small phones, light + dark, RTL not needed
(English only), 130-char Telegram/ad text, font scale up to 1.3.

## 6. Not UI work (don't touch)

`lib/domain/*` crypto/token/tamper, `android/**` (VpnService, native `libovs.so`), `server/**`, `tool/**`,
`.github/workflows/**`. Run `dart format` + `flutter analyze --fatal-infos` + `flutter test` before pushing;
CI also takes screenshots of the key screens (`test/` UI smoke tests) — update them if screens change.
