#!/usr/bin/env bash
# End-to-end proof that the gate works against real Xray:
#   curl --socks5 -> Xray client (config built by the app's Dart builder)
#        -> gate (:8081) -> Xray server ws inbound (:10000) -> local web server (:9099)
# Three clients, one server:
#   owner   token for (app key, lock code, OWNER fingerprint)   -> must reach the origin
#   plain   no token (a decoded link pasted into any other app) -> must be refused
#   thief   same code + app key, but the file was re-locked under the thief's own
#           fingerprint, so the app computes the token with THEIR fingerprint
#           -> must be refused, because the allow-list pins the owner's fingerprint
# Finally the allow-list line is deleted: the owner must stop working (revocation).
#
#   XRAY=/path/to/xray tool/e2e_gate.sh      (needs flutter/dart, go, python3, curl)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XRAY="${XRAY:-xray}"
W="${W:-$(mktemp -d)}"; trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
UUID=11111111-2222-3333-4444-555555555555
KEY=e2e-test-key
CODE=0123456789abcdef0123456789abcdef
OWNER_FP=3FA9-0C21-B7D4-9E10
THIEF_FP=AAAA-BBBB-CCCC-DDDD
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

(cd "$ROOT/server" && go build -o "$W/oversee" ./cmd/oversee)
echo "$CODE $OWNER_FP e2e" > "$W/allow.txt"
# keys file: newest first; "old-key" stands in for a previous release
printf '%s\n%s\n' "$KEY" "old-key" > "$W/keys.txt"
OVERSEE_DIR="$W" "$W/oversee" gate -plain 127.0.0.1:8081 -upstream 127.0.0.1:10000 -allow "$W/allow.txt" -keys "$W/keys.txt" >"$W/gate.log" 2>&1 &

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
PORT_=10801 mk owner "$KEY" "$CODE" "$OWNER_FP"
PORT_=10802 mk plain
PORT_=10803 mk thief "$KEY" "$CODE" "$THIEF_FP"
for n in owner plain thief; do "$XRAY" run -c "$W/$n.json" >"$W/$n.log" 2>&1 & done
sleep 4

fetch() { curl -sS -m 6 --socks5-hostname "127.0.0.1:$1" "http://$ORIGIN_IP:9099/index.html" 2>&1 || true; }
OK="page-from-origin"
A="$(fetch 10801)"; B="$(fetch 10802)"; C="$(fetch 10803)"
echo "owner            : ${A:0:60}"
echo "plain (no token) : ${B:0:60}"
echo "thief (re-locked): ${C:0:60}"
[[ "$A" == *$OK* ]] || { echo "FAIL: owner could not reach origin"; tail -n 5 "$W/gate.log"; exit 1; }
[[ "$B" != *$OK* ]] || { echo "FAIL: client without token got through"; exit 1; }
[[ "$C" != *$OK* ]] || { echo "FAIL: re-locked copy (other creator) got through"; exit 1; }

# Live stats written by the gate (what the TUI shows): the owner's lock was used from
# exactly 1 IP, and the refusals were counted. No raw IPs on disk.
sleep 6
python3 - "$W/stats.json" <<'PY'
import json,sys
sn=json.load(open(sys.argv[1]))
assert len(sn["locks"])==1 and sn["locks"][0]["distinctIps"]==1 and sn["locks"][0]["accepted"]>=1, sn
assert sum(sn["rejects"].values())>=1, sn
assert "127.0.0.1" not in open(sys.argv[1]).read()
print("stats ok:", sn["locks"][0], sn["rejects"])
PY

# Revocation: delete the line; the gate reloads within a few seconds.
: > "$W/allow.txt"
sleep 5
D="$(fetch 10801)"
echo "owner, revoked   : ${D:0:60}"
[[ "$D" != *$OK* ]] || { echo "FAIL: revoked lock still works"; exit 1; }
echo "PASS"
