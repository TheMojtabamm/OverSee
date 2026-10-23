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

openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=e2e.test" \
  -keyout "$OUT/key.pem" -out "$OUT/cert.pem" >/dev/null 2>&1
CERT="$PWD/$OUT/cert.pem"; KEY="$PWD/$OUT/key.pem"

cat > "$OUT/server.json" <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"0.0.0.0","port":8443,"protocol":"vless",
   "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
   "streamSettings":{"network":"tcp"}},
  {"listen":"0.0.0.0","port":8444,"protocol":"vless",
   "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
   "streamSettings":{"network":"ws","wsSettings":{"path":"/ws"},"security":"tls",
     "tlsSettings":{"certificates":[{"certificateFile":"$CERT","keyFile":"$KEY"}]}}}],
 "outbounds":[{"protocol":"freedom"}]}
EOF
"$XRAY" run -c "$OUT/server.json" > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 2

link_for() {
  case "$1" in
    ws) echo "vless://$UUID@10.0.2.2:8444?encryption=none&security=tls&sni=e2e.test&allowInsecure=1&type=ws&path=%2Fws&host=e2e.test" ;;
    *)  echo "vless://$UUID@10.0.2.2:8443?encryption=none&security=none&type=tcp" ;;
  esac
}

echo "== build + install the debug app, pre-grant the VPN consent =="
flutter build apk --debug --target-platform android-x64 >/dev/null 2>"$OUT/build.err" || { tail -20 "$OUT/build.err"; exit 1; }
adb install -r -t build/app/outputs/flutter-apk/app-debug.apk || exit 1
adb shell appops set $PKG ACTIVATE_VPN allow
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS 2>/dev/null || true
# the test reinstalls the app; keep the consent in place if that resets it
( while true; do adb shell appops set $PKG ACTIVATE_VPN allow >/dev/null 2>&1; sleep 3; done ) &
KEEP=$!

run_case() {
  DNSMODE="$1"; KIND="$2"; MODE="$DNSMODE-$KIND"; LINK="$(link_for "$KIND")"
  echo; echo "################ DNS=$DNSMODE transport=$KIND ################"
adb logcat -c
echo "== run the integration test =="
flutter test integration_test/tunnel_e2e_test.dart -d emulator-5554 \
  --dart-define=E2E_LINK="$LINK" --dart-define=E2E_DNS="$DNSMODE" > "$OUT/test-$MODE.log" 2>&1 &
TEST=$!

# `flutter test` only relays the app's prints late; the marker is in logcat the moment it happens.
UP=0
for i in $(seq 1 120); do
  # The test's own print is not in logcat; its probe request (made right after the tunnel is up)
  # is: Xray logs "tunneling request to tcp:example.com:80" for it.
  if adb logcat -d 2>/dev/null | grep -q "tunneling request to tcp:example.com:80"; then UP=1; break; fi
  kill -0 $TEST 2>/dev/null || break
  sleep 2
done


if [ "$UP" = 1 ]; then
  echo "== tunnel is up; checking traffic from adb shell (goes through the VPN) =="
  sleep 2
  {
    echo "--- routes / VPN"; adb shell ip route; adb shell dumpsys connectivity | grep -iE "VPN|Active default" | head -8
  } > "$OUT/checks-$MODE.txt" 2>&1
  D=$(adb shell "printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | nc -w 12 example.com 80 | head -n 1" 2>&1 | tr -d '\r')
  I=$(adb shell "printf 'GET / HTTP/1.0\r\nHost: example.com\r\n\r\n' | nc -w 12 93.184.215.14 80 | head -n 1" 2>&1 | tr -d '\r')
  cat "$OUT/checks-$MODE.txt"
  echo "RESULT[$MODE] by name (needs DNS through the tunnel): ${D:-<nothing>}"
  echo "RESULT[$MODE] by raw IP (no DNS):                     ${I:-<nothing>}"
  case "$I" in HTTP/1*) ;; *) echo "!! [$MODE] RAW-IP TRAFFIC DOES NOT FLOW"; RESULT=1;; esac
  case "$D" in HTTP/1*) ;; *) echo "!! [$MODE] DNS/NAME TRAFFIC DOES NOT FLOW"; RESULT=1;; esac
else
  echo "!! tunnel did not come up / UI never connected"; RESULT=1
  echo "--- flutter test log (tail) ---"; tail -40 "$OUT/test-$MODE.log" 2>/dev/null
  echo "--- xray/server log (tail) ---"; tail -15 "$OUT/server.log" 2>/dev/null
fi

  wait $TEST; TRC=$?
  adb logcat -d > "$OUT/logcat-$MODE.txt"
  echo "== integration test output ($MODE) =="; grep -E "E2E_|Some tests failed|All tests passed|Expected|Actual|\[E\]" "$OUT/test-$MODE.log" | head -30
  echo "== client core log ($MODE) =="
  grep -iE "GoLog|xray|failed|error|dial|dns" "$OUT/logcat-$MODE.txt" | grep -viE "chromium|gms|vending" | tail -50
  [ $TRC -ne 0 ] && RESULT=1
  return 0
}


RESULT=0
run_case plain tcp
run_case plain ws
run_case doh tcp
kill $KEEP $SERVER 2>/dev/null
echo "== server log =="; tail -20 "$OUT/server.log"
exit $RESULT
