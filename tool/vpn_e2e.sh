#!/usr/bin/env bash
# Real-data-path test on an Android emulator: starts the app's VpnService + Xray tun against a
# local Xray server (vless/tcp on the host, reachable from the emulator at 10.0.2.2) and checks,
# from `adb shell` (which IS routed through the VPN), that DNS and TCP work through the tunnel.
#
#   XRAY=/path/to/xray tool/vpn_e2e.sh      (run inside an emulator session)
set -u
XRAY="${XRAY:?path to the xray binary}"
PKG=com.oversea.oversea
UUID=11111111-2222-3333-4444-555555555555
OUT=build/vpn_e2e; mkdir -p "$OUT"

cat > "$OUT/server.json" <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"0.0.0.0","port":8443,"protocol":"vless",
   "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
   "streamSettings":{"network":"tcp"}}],
 "outbounds":[{"protocol":"freedom"}]}
EOF
"$XRAY" run -c "$OUT/server.json" > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 2

LINK="vless://$UUID@10.0.2.2:8443?encryption=none&security=none&type=tcp"

echo "== build + install the debug app, pre-grant the VPN consent =="
flutter build apk --debug --target-platform android-x64 >/dev/null 2>"$OUT/build.err" || { tail -20 "$OUT/build.err"; exit 1; }
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk || exit 1
adb shell appops set $PKG ACTIVATE_VPN allow
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null || true
# the test reinstalls the app; keep the consent in place if that resets it
( while true; do adb shell appops set $PKG ACTIVATE_VPN allow >/dev/null 2>&1; sleep 3; done ) &
KEEP=$!

adb logcat -c
echo "== run the integration test =="
flutter test integration_test/tunnel_e2e_test.dart -d emulator-5554 \
  --dart-define=E2E_LINK="$LINK" > "$OUT/test.log" 2>&1 &
TEST=$!

for i in $(seq 1 120); do
  grep -q "E2E_TUNNEL_UP" "$OUT/test.log" && break
  kill -0 $TEST 2>/dev/null || break
  sleep 3
done

RESULT=0
if grep -q "E2E_TUNNEL_UP" "$OUT/test.log"; then
  echo "== tunnel is up; checking traffic from adb shell (goes through the VPN) =="
  sleep 3
  {
    echo "--- routes / VPN"; adb shell ip route; adb shell dumpsys connectivity | grep -iE "VPN|Active default" | head -8
    echo "--- DNS + TCP through the tunnel: example.com:80"
    adb shell "printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | nc -w 12 example.com 80 | head -n 1"
    echo "--- raw IP, no DNS: 93.184.215.14:80 (example.com)"
    adb shell "printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | nc -w 12 93.184.215.14 80 | head -n 1"
  } > "$OUT/checks.txt" 2>&1
  cat "$OUT/checks.txt"
  grep -q "^HTTP/1" "$OUT/checks.txt" || { echo "!! NO INTERNET THROUGH THE TUNNEL"; RESULT=1; }
else
  echo "!! tunnel did not come up / UI never connected"; RESULT=1
fi

wait $TEST; TRC=$?
kill $KEEP $SERVER 2>/dev/null
adb logcat -d > "$OUT/logcat.txt"
echo "== integration test output =="; grep -E "E2E_|Some tests failed|All tests passed|Expected|Actual|\[E\]" "$OUT/test.log" | head -30
echo "== xray (GoLog / errors from the client core) =="
grep -iE "GoLog|xray|failed|error|dial|dns" "$OUT/logcat.txt" | grep -viE "chromium|gms|vending" | tail -60
echo "== server log =="; tail -20 "$OUT/server.log"
[ $TRC -ne 0 ] && RESULT=1
exit $RESULT
