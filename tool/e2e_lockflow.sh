#!/usr/bin/env bash
# "If the config is decoded, it is useless to everyone except the real file in our app."
# Real Xray + real gate + the real app code (lock -> decode -> import -> connect):
#
#   app    the owner's locked file, opened in the app            -> MUST reach the origin
#   bot    the config a decoder bot recovers (plain link)        -> MUST be refused
#   thief  that config re-locked under another identity, in app  -> MUST be refused
#   then the owner revokes the lock                              -> app MUST stop working
#
#   XRAY=/path/to/xray tool/e2e_lockflow.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XRAY="${XRAY:-xray}"
W="${W:-$(mktemp -d)}"; trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
UUID=11111111-2222-3333-4444-555555555555
GATEKEY=lockflow-app-key-0123456789
ORIGIN_IP="$(hostname -I | awk '{print $1}')"
[ -n "$ORIGIN_IP" ] || { echo "no non-loopback IP available"; exit 2; }
LINK="vless://$UUID@127.0.0.1:8081?encryption=none&security=none&type=ws&path=%2Fws#lockflow"

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

echo "== lock -> decode -> import (real app code)"
(cd "$ROOT" && dart run -DLOCK_P1=aaaaaaaaaaaaaaaa -DLOCK_P2=bbbbbbbbbbbbbbbb -DLOCK_P3=cccccccccccccccc \
   -DLOCK_P4=dddddddddddddddd -DGATE_KEY="$GATEKEY" tool/e2e_lockflow.dart "$W/flow" "$LINK")
echo "   a decoder bot would paste this into other apps: $(cat "$W/flow/decoded_link.txt" | cut -c1-70)…"

(cd "$ROOT/server" && go build -o "$W/oversee" ./cmd/oversee)
printf '%s\n' "$GATEKEY" > "$W/keys.txt"
OVERSEE_DIR="$W" "$W/oversee" gate -plain 127.0.0.1:8081 -upstream 127.0.0.1:10000 \
  -allow "$W/flow/allow.txt" -keys "$W/keys.txt" >"$W/gate.log" 2>&1 &

socksify() { python3 -c '
import json,sys
c=json.load(open(sys.argv[1]))
c["inbounds"]=[{"tag":"socks","listen":"127.0.0.1","port":int(sys.argv[2]),"protocol":"socks","settings":{"udp":False}}]
c["routing"]["rules"]=[r for r in c["routing"]["rules"] if r.get("outboundTag")!="direct"]
c["dns"]={"servers":["localhost"]}
json.dump(c,open(sys.argv[3],"w"))' "$1" "$2" "$3"; }
socksify "$W/flow/app.json"   10801 "$W/app.json"
socksify "$W/flow/bot.json"   10802 "$W/bot.json"
socksify "$W/flow/thief.json" 10803 "$W/thief.json"
for n in app bot thief; do "$XRAY" run -c "$W/$n.json" >"$W/$n.log" 2>&1 & done
sleep 5

fetch() { curl -sS -m 6 --socks5-hostname "127.0.0.1:$1" "http://$ORIGIN_IP:9099/index.html" 2>&1 || true; }
OK="page-from-origin"
A="$(fetch 10801)"; B="$(fetch 10802)"; T="$(fetch 10803)"
echo "== results"
echo "app (owner's file)            : ${A:0:50}"
echo "bot (decoded plain link)      : ${B:0:50}"
echo "thief (re-locked, in the app) : ${T:0:50}"
[[ "$A" == *$OK* ]] || { echo "FAIL: the real file in the app could not connect"; tail -n 5 "$W/gate.log"; exit 1; }
[[ "$B" != *$OK* ]] || { echo "FAIL: the DECODED config works outside the app"; exit 1; }
[[ "$T" != *$OK* ]] || { echo "FAIL: a re-locked copy works"; exit 1; }

: > "$W/flow/allow.txt"; sleep 5          # the owner revokes the lock
R="$(fetch 10801)"
echo "app after the owner revokes   : ${R:0:50}"
[[ "$R" != *$OK* ]] || { echo "FAIL: a revoked lock still works"; exit 1; }
echo "PASS: decoded config is useless; only the owner's file, through the app, connects"
