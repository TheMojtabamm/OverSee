#!/usr/bin/env bash
# End-to-end proof that the gate works against real Xray:
#   curl --socks5 -> Xray client (config built by the app's Dart builder)
#        -> gate (:8081) -> Xray server ws inbound (:10000) -> local web server (:9099)
# Expectations: WITH token = page returned. WITHOUT token (a decoded plain link
# pasted into any other client) = connection refused by the gate.
#
#   XRAY=/path/to/xray tool/e2e_gate.sh      (needs flutter/dart, go, python3, curl)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XRAY="${XRAY:-xray}"
W="${W:-$(mktemp -d)}"; trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
UUID=11111111-2222-3333-4444-555555555555
KEY=e2e-test-key
LINK="vless://$UUID@127.0.0.1:8081?encryption=none&security=none&type=ws&path=%2Fws#e2e"

# (The test server's freedom outbound allows private targets via finalRules=[allow]; the
# default blocks them, which is what you want on a real server.)
# Xray sends loopback destinations straight out ("direct") regardless of the proxy,
# so the origin must live on a non-loopback address to prove the proxy path.
ORIGIN_IP="$(hostname -I | awk '{print $1}')"
[ -n "$ORIGIN_IP" ] || { echo "no non-loopback IP available"; exit 2; }
echo "page-from-origin" > "$W/index.html"
(cd "$W" && python3 -m http.server 9099 --bind "$ORIGIN_IP" >/dev/null 2>&1) &

cat > "$W/server.json" <<EOF
{"log":{"loglevel":"warning"},
 "inbounds":[{"listen":"127.0.0.1","port":10000,"protocol":"vless",
   "settings":{"clients":[{"id":"$UUID"}],"decryption":"none"},
   "streamSettings":{"network":"ws","wsSettings":{"path":"/ws"}}}],
 "outbounds":[{"protocol":"freedom","settings":{"finalRules":[{"action":"allow"}]}}]}
EOF
"$XRAY" run -c "$W/server.json" >"$W/server.log" 2>&1 &

(cd "$ROOT/server" && go build -o "$W/gate" ./cmd/gate)
GATE_KEYS="old-key,$KEY" "$W/gate" -plain 127.0.0.1:8081 -upstream 127.0.0.1:10000 >"$W/gate.log" 2>&1 &

# Client configs from the app's builder; swap the Android tun inbound for socks.
mk() { # name, extra-args...
  (cd "$ROOT" && dart run tool/e2e_client_config.dart "$LINK" "${@:2}") | python3 -c '
import json,sys
c=json.load(sys.stdin)
c["inbounds"]=[{"tag":"socks","listen":"127.0.0.1","port":int(sys.argv[1]),"protocol":"socks","settings":{"udp":False}}]
c["routing"]["rules"]=[r for r in c["routing"]["rules"] if r.get("outboundTag")!="direct"]
c["dns"]={"servers":["localhost"]}
print(json.dumps(c))' "$PORT_" > "$W/$1.json"
}
PORT_=10801 mk gated "$KEY"
PORT_=10802 mk plain
"$XRAY" run -c "$W/gated.json" >"$W/gated.log" 2>&1 &
"$XRAY" run -c "$W/plain.json" >"$W/plain.log" 2>&1 &
sleep 4

fetch() { curl -sS -m 8 --socks5-hostname "127.0.0.1:$1" http://$ORIGIN_IP:9099/index.html 2>&1 || true; }
A="$(fetch 10801)"; B="$(fetch 10802)"
echo "with gate token   : $A"
echo "without token     : ${B:-<empty>}"
[[ "$A" == *page-from-origin* ]] || { echo "FAIL: gated client could not reach origin"; tail -n 5 "$W/gated.log"; tail -n 5 "$W/gate.log"; exit 1; }
[[ "$B" != *page-from-origin* ]] || { echo "FAIL: ungated client got through"; exit 1; }
echo "PASS"
