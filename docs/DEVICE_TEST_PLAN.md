# Device test plan (step 25)

Nothing below has been run yet: I can build and unit-test, but there is no phone or
emulator with VPN support in the build environment. Run this on at least: a recent
Pixel/Android 14-15, a Samsung (One UI), a Xiaomi/Redmi (MIUI/HyperOS, aggressive
task killing), and one Android 7-9 device (minSdk 24).

Install: `adb install -r app-release.apk`; watch `adb logcat -s OverseaVpn:* AndroidRuntime:E`.
Use a config you control (a VLESS+Reality server) plus one dead config.

## Connect / disconnect
- [ ] First tap on a config: disclosure → system VPN prompt → connected; status card + notification show.
- [ ] Deny the VPN prompt: snackbar, no crash, no half-started service.
- [ ] Notification "Disconnect" button stops the tunnel; app UI updates.
- [ ] Dead config: fails within ~25 s with "Could not connect", service stops, no stuck notification.
- [ ] Switch between two configs while connected.
- [ ] https://ifconfig.me shows the server IP while connected and the real IP after.

## Leaks
- [ ] DNS leak test (dnsleaktest.com) shows only the DoH resolver's/server's side, not the ISP.
- [ ] IPv6 test (test-ipv6.com): no IPv6 reachability with the IPv6 setting off.
- [ ] WebRTC leak test in Chrome.
- [ ] LAN bypass: casting / router page reachable when on; routed through tunnel when off.

## Kill switch
- [ ] Stop the VPN server (or block it) mid-session: traffic is blocked, status "Blocked", no leak to real IP.
- [ ] Kill switch off: connection drop disconnects cleanly.
- [ ] System Settings → VPN → Always-on + "Block connections without VPN": reboot; before opening the app no traffic leaks; opening the app and tapping a config restores it.
- [ ] Another VPN app takes over: our tunnel stops (onRevoke), no crash.

## Network changes
- [ ] Wi-Fi → mobile data → Wi-Fi while a download runs: new connections work within seconds.
- [ ] Airplane mode on/off.
- [ ] Doze: leave connected overnight with screen off; check battery stats (target: < 2 %/h idle) and that the notification is still there.

## Per-app
- [ ] "Only selected": only chosen apps show the VPN IP.
- [ ] "Except selected": chosen apps show the real IP.
- [ ] App list loads without QUERY_ALL_PACKAGES on Android 11+.

## Locking
- [ ] Lock & share creates a `.ovsea` file; no plaintext in the share text. Open in a second install: server hidden, no copy/share, connects.
- [ ] Creator fingerprint shown; "Trust" persists across restart.
- [ ] Re-locking a copy under another install shows a different fingerprint.
- [ ] Screenshot / Recents thumbnail are blank (FLAG_SECURE).
- [ ] Upgrade from the previous build: old configs migrated, plaintext copy gone.

## Ads
- [ ] Test ads only (no real unit id): none on first-ever connect; one after a later connect; none within 5 minutes.
- [ ] EEA VPN-location / UMP debug geography: consent form appears before any ad; "Ad privacy options" appears in Settings.
- [ ] Disconnecting before the ad would show: no ad appears.

## Ping
- [ ] Per-config ping and "Test all" show sensible ms, mark dead ones "failed", list sorts fastest-first.
- [ ] Works with the VPN off and on.
